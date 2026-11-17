// 688 性能负载基线统计（只读，不改任何文件）
//   ① 存档体积 / 记录数 / 隐藏层分布
//   ② 内嵌 Lua 体积构成
//   ③ 每帧同步链的静态工作量（SETTLE_ART_TINT / BLOCK640 等）
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const GIL = path.join(ROOT, 'qianxing-murdoku/688_第4至7关接入/688_第4至7关接入.gil');
const LUA = path.join(ROOT, 'qianxing-murdoku/688_第4至7关接入/688_内嵌Lua_688.lua');
const url = p => pathToFileURL(p).href;
const { readGil } = await import(url(path.join(TOOLS, 'gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));

const g = readGil(GIL);
const isHidden = f => {
  let hidden = false;
  for (const x of f.sub || []) {
    if (x.field !== 505 || !x.sub) continue;
    (function walk(a, p) {
      for (const y of a) {
        const pp = p + '/' + y.field;
        if (y.wt === 0 && pp === '/503/14/17/503') hidden = true;
        else if (y.sub) walk(y.sub, pp);
      }
    })(x.sub, '');
  }
  return hidden;
};
const hidden = g.recs.filter(r => isHidden(r.field));
const byPrefix = {};
for (const r of hidden) {
  const k = (r.name || '').split('.').slice(0, 2).join('.') || '(无名)';
  byPrefix[k] = (byPrefix[k] || 0) + 1;
}
const top = Object.entries(byPrefix).sort((a, b) => b[1] - a[1]).slice(0, 18);

const luaBuf = fs.readFileSync(LUA);
const lua = luaBuf.toString('utf8');
const lines = lua.split('\n');
const blank = lines.filter(s => s.trim() === '').length;
const comment = lines.filter(s => /^\s*--/.test(s)).length;
const scriptLeaf = findScriptLeaf(g);
const embedded = scriptLeaf.buf.toString('utf8');

// 每帧同步链：从真实源码里数出被遍历的条目数
const tint = lua.match(/local SETTLE_ART_TINT = \{([\s\S]*?)\n\}/);
const tintN = tint ? (tint[1].match(/\{\s*"art647\./g) || []).length : -1;
const block = lua.match(/local BLOCK640 = \{([\s\S]*?)\n\}/);
const blockN = block ? (block[1].match(/tag\s*=/g) || []).length : -1;
const list = lua.match(/local LIST = \{([\s\S]*?)\n\}/);
const listN = list ? (list[1].match(/"levels\.case_/g) || []).length : -1;

const out = {
  file: GIL,
  sha256: crypto.createHash('sha256').update(fs.readFileSync(GIL)).digest('hex'),
  bytes: fs.statSync(GIL).size,
  records: g.recs.length,
  hiddenRecords: hidden.length,
  visibleRecords: g.recs.length - hidden.length,
  hiddenTopPrefixes: Object.fromEntries(top),
  embeddedLua: {
    bytes: Buffer.byteLength(embedded),
    lines: lines.length,
    blankLines: blank,
    commentLines: comment,
    blankPlusCommentBytes: Buffer.byteLength(lines.filter(s => s.trim() === '' || /^\s*--/.test(s)).join('\n')),
  },
  perFrameChain: {
    settleArtTintEntries: tintN,
    block640Entries: blockN,
    registeredLevels: listN,
    markOverlayCtrls: 8 * 8 * 3,
    syncFunctions: ['Murdoku.on_update', 'sync_art641', 'sync_art647', 'sync_art649_page', 'sync_block640', 'Adapter:on_tick'],
  },
};
fs.writeFileSync(path.join(DIR, '689_负载基线.json'), JSON.stringify(out, null, 2));
console.log(JSON.stringify(out, null, 2));
