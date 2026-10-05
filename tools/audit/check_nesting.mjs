#!/usr/bin/env node
// tools/audit/check_nesting.mjs —— 机械扫描「块嵌套与缩进不一致」的 Lua 源文件
//
// 为什么需要它（本轮实测抓到的两个真凶都是这个形状）：
//   Lua 里 `end` 配对错位**不会报错**（只要总数平衡，文件照样编译通过），
//   但会把后面的**顶层语句吞进上面某个块里**。代价是"整个功能静默失效"：
//     · `lua/engine_adapter_qianxing.lua` 的 `if self.cfg.btn_art == true and print then`
//       没被关闭 ⇒ `Adapter:apply_ruler_layout` / `Adapter:diagnose_overlap`
//       两个**方法定义**被吞进 `apply_tray_layout` 的函数体 ⇒ 加载时根本不存在
//       ⇒ 调用点的 `if adapter.xxx ~= nil then` 守卫静默跳过 ⇒ 功能从未运行、零报错。
//     · `lua/main.lua` 的 `if (current.frames or 0) % 300 == 0 then` 没被关闭
//       ⇒ 把"每帧压住 selbar / 每 30 帧点亮 face"整段套进去 ⇒ 节流变成每 300 帧。
//   判据（**只看缩进与块深度的矛盾**，不猜语义）：
//     **缩进为 0（作者认为它是顶层）的 `function` / `if` / `for` / `while` / `do`，
//       如果它所在的块深度 > 0 ⇒ 必然是 `end` 配对错位。**
//   这条判据在本仓的历史 bug 上是**零误报**的（见文件末尾的判读说明）。
//
// 跑法：node tools/audit/check_nesting.mjs [文件或目录 ...]
//       不给参数 = 扫 lua/**.lua
// 退出码：0 = 干净；1 = 有命中；2 = 读文件失败
//
// ⚠️ 本工具**只读**，不修改任何文件。

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SELF = fileURLToPath(import.meta.url);
const ROOT = path.resolve(path.dirname(SELF), '..', '..');

// ── 1. 去掉注释与字符串（保留换行，行号才不会漂）────────────────────────────
export function blankCommentsAndStrings(src) {
  const out = Buffer.from(src, 'utf8');           // 按字节处理 ASCII 结构符即可
  const n = out.length;
  let i = 0;
  const blank = (from, to) => { for (let k = from; k < to && k < n; k++) if (out[k] !== 10 && out[k] !== 13) out[k] = 32; };
  while (i < n) {
    const c = out[i];
    // 长括号 [[ / [=[ …
    if (c === 91 /* [ */) {
      let j = i + 1, eq = 0;
      while (j < n && out[j] === 61 /* = */) { eq++; j++; }
      if (j < n && out[j] === 91) {
        const close = Buffer.from(']' + '='.repeat(eq) + ']', 'utf8');
        const end = out.indexOf(close, j + 1);
        const stop = end === -1 ? n : end + close.length;
        blank(i, stop);
        i = stop;
        continue;
      }
      i++; continue;
    }
    // 行注释 / 长注释
    if (c === 45 /* - */ && out[i + 1] === 45) {
      let j = i + 2;
      if (out[j] === 91) {                       // --[[ 长注释
        let k = j + 1, eq = 0;
        while (k < n && out[k] === 61) { eq++; k++; }
        if (k < n && out[k] === 91) {
          const close = Buffer.from(']' + '='.repeat(eq) + ']', 'utf8');
          const end = out.indexOf(close, k + 1);
          const stop = end === -1 ? n : end + close.length;
          blank(i, stop);
          i = stop;
          continue;
        }
      }
      let k = j;
      while (k < n && out[k] !== 10) k++;        // 普通行注释
      blank(i, k);
      i = k;
      continue;
    }
    // 短字符串
    if (c === 34 || c === 39) {
      let k = i + 1;
      while (k < n) {
        if (out[k] === 92 /* \ */) { k += 2; continue; }
        if (out[k] === c) { k++; break; }
        if (out[k] === 10) break;                // 未闭合（源文件本来就坏了）
        k++;
      }
      blank(i + 1, Math.min(k, n) - 1);
      i = k;
      continue;
    }
    i++;
  }
  return out.toString('utf8');
}

// ── 2. 词法：按行给出"这一行出现的关键字 + 该行之前的块深度"──────────────────
const NEED_END = new Set(['function', 'if', 'do', 'for', 'while', 'repeat']);

export function scanBlocks(src) {
  const clean = blankCommentsAndStrings(src);
  const lines = clean.split(/\r?\n/);
  let depth = 0, pendingDo = 0;
  const rows = [];
  for (let li = 0; li < lines.length; li++) {
    const before = depth;
    const text = lines[li];
    // 取标识符（Lua 关键字只由字母组成）
    const re = /[A-Za-z_][A-Za-z0-9_]*/g;
    let m;
    const kws = [];
    while ((m = re.exec(text)) !== null) kws.push(m[0]);
    for (const w of kws) {
      switch (w) {
        case 'function': depth++; break;
        case 'if': depth++; break;                 // elseif 是另一个标识符，不会误计
        case 'for': case 'while': depth++; pendingDo++; break;
        case 'do':
          if (pendingDo > 0) pendingDo--; else depth++;
          break;
        case 'end': depth--; break;
        case 'repeat': depth++; break;
        case 'until': depth--; break;
        default: break;
      }
    }
    rows.push({ line: li + 1, text, depthBefore: before, depthAfter: depth });
  }
  return { rows, finalDepth: depth };
}

// ── 3. 判据：缩进 0 的块开头，块深度却 > 0 ──────────────────────────────────
const TOP_DECL = /^(local\s+)?function\s/;
const TOP_BLOCK = /^(if|for|while|do|repeat)\b/;

export function checkFile(file) {
  let src;
  try { src = fs.readFileSync(file, 'utf8'); } catch (e) { return { file, error: String(e) }; }
  const { rows, finalDepth } = scanBlocks(src);
  const hits = [];
  for (const r of rows) {
    if (r.text.length === 0 || /^\s/.test(r.text)) continue;   // 只看**顶格**的行
    const isDecl = TOP_DECL.test(r.text);
    const isBlock = TOP_BLOCK.test(r.text);
    if ((isDecl || isBlock) && r.depthBefore > 0) {
      hits.push({ line: r.line, depth: r.depthBefore, kind: isDecl ? 'function' : 'block', text: r.text.trim() });
    }
  }
  return { file, hits, finalDepth };
}

// ── 4. CLI ─────────────────────────────────────────────────────────────────
function walk(p, acc) {
  const st = fs.statSync(p);
  if (st.isDirectory()) {
    for (const e of fs.readdirSync(p)) walk(path.join(p, e), acc);
  } else if (p.endsWith('.lua')) acc.push(p);
  return acc;
}

const isMain = process.argv[1] && path.resolve(process.argv[1]) === path.resolve(new URL(import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1'));
if (isMain) {
  const args = process.argv.slice(2);
  const targets = args.length ? args : [path.join(ROOT, 'lua')];
  const files = [];
  for (const t of targets) {
    try { walk(path.resolve(t), files); }
    catch (e) { console.error('读不了 ' + t + '：' + e.message); process.exit(2); }
  }
  files.sort();
  let bad = 0, unbalanced = 0;
  for (const f of files) {
    const r = checkFile(f);
    if (r.error) { console.error('读不了 ' + f + '：' + r.error); bad++; continue; }
    const rel = path.relative(ROOT, f).replace(/\\/g, '/');
    if (r.finalDepth !== 0) {
      unbalanced++;
      console.log(`[不平衡] ${rel}  —— 全文扫完块深度 = ${r.finalDepth}（应为 0）`);
    }
    for (const h of r.hits) {
      bad++;
      console.log(`[嵌套] ${rel}:${h.line}  深度=${h.depth}  ${h.kind}  ::  ${h.text}`);
    }
  }
  console.log('');
  console.log(`扫描 ${files.length} 个 .lua；命中 ${bad} 处；块深度不平衡 ${unbalanced} 个文件。`);
  console.log('判读：`[嵌套]` = 顶格写的块开头，实际落在别的块里面 ⇒ `end` 配对错位。');
  console.log('      Lua 不会为此报错，代价是**后面的顶层语句被吞进上面的块**（功能静默失效）。');
  process.exit(bad === 0 && unbalanced === 0 ? 0 : 1);
}
