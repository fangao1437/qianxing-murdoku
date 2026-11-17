// 689 独立结构校验（不复用构建脚本的断言对象）
//   ① 687/688 基准 SHA 与交付文档一致 ⇒ 历史版本未被破坏
//   ② 688→689 记录表 7921 条逐字节全同（rogue=0，隐藏/可见层计数不变）
//   ③ 689 内嵌 Lua 反向补丁 + 空白行还原逐字节回到 688
//   ④ 静态文本 75 处 / 前 3 关 / 7 关注册 / 无未注册线索类型
//   ⑤ luac -p 双份语法闸门
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const TOOLS = path.join(ROOT, 'qianxing-murdoku-tool/project-tools/gil');
const P688 = path.join(REPO, '688_第4至7关接入/688_第4至7关接入.gil');
const P689 = path.join(DIR, '689_性能负载优化.gil');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg } = await import(url(path.join(TOOLS, 'gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(TOOLS, 'gilwrite.mjs')));
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const PATCH = JSON.parse(fs.readFileSync(path.join(DIR, '689_性能补丁.json'), 'utf8'));
const checks = [];
const ck = (name, ok, detail) => { checks.push({ name, ok: !!ok, detail }); if (!ok) console.log('  FAIL', name, detail); };

const g688 = readGil(P688), g689 = readGil(P689);
const s688 = findScriptLeaf(g688).buf.toString('utf8');
const s689 = findScriptLeaf(g689).buf.toString('utf8');
const A = new Map(g688.recs.map(r => [r.id, r]));
const B = new Map(g689.recs.map(r => [r.id, r]));

// ① 基准 SHA
const SHA687 = '8d33d9af7592ff2a8d9b9af37838c606fff3d816762fdaed984a4e4143a169fe';
const SHA688 = '337510627ba91121e2df3a9713b4e1d260e3ce681fd3f91e4042d1c6137dff6d';
ck('687 基准 SHA 未改', sha(path.join(REPO, '687_综合整改/687_综合整改.gil')) === SHA687, SHA687.slice(0, 12));
ck('688 基准 SHA 未改', sha(P688) === SHA688, SHA688.slice(0, 12));
ck('689 与 688 不是同一文件', sha(P689) !== SHA688, sha(P689).slice(0, 12));

// ② 记录表逐字节
let changed = 0, lost = 0;
for (const [id, r] of A) {
  const q = B.get(id);
  if (!q) { lost++; continue; }
  if (!encodeMsg([r.field]).equals(encodeMsg([q.field]))) changed++;
}
ck('记录数 = 7921', g688.recs.length === 7921 && g689.recs.length === 7921,
   g688.recs.length + '/' + g689.recs.length);
ck('旧记录丢失 = 0', lost === 0, lost);
ck('记录表逐字节零改动 (rogue=0)', changed === 0, changed);
const isHidden = f => {
  let h = false;
  for (const x of f.sub || []) {
    if (x.field !== 505 || !x.sub) continue;
    (function walk(a, p) {
      for (const y of a) {
        const pp = p + '/' + y.field;
        if (y.wt === 0 && pp === '/503/14/17/503') h = true;
        else if (y.sub) walk(y.sub, pp);
      }
    })(x.sub, '');
  }
  return h;
};
const h688 = g688.recs.filter(r => isHidden(r.field)).length;
const h689 = g689.recs.filter(r => isHidden(r.field)).length;
ck('隐藏层计数不变 (945)', h688 === h689 && h689 === 945, h688 + '/' + h689);

// ③ 反向逐字节还原 688 Lua
function strip(s) {
  const kept = [], blanks = [];
  for (const ln of s.split('\n')) {
    if (/^[ \t\r]*$/.test(ln)) blanks.push([kept.length, ln]);
    else kept.push(ln);
  }
  const groups = new Map();
  for (const [k, txt] of blanks) { if (!groups.has(k)) groups.set(k, []); groups.get(k).push(txt); }
  return { text: kept.join('\n'), groups, removed: blanks.length };
}
function restore(s, groups) {
  const arr = s.split('\n');
  for (let k = arr.length; k >= 0; k--) {
    const it = groups.get(k);
    if (it) arr.splice(k, 0, ...it);
  }
  return arr.join('\n');
}
function locate(s, p) {
  let from = 0;
  if (p.anchor) from = s.indexOf(p.anchor) + p.anchor.length;
  const i0 = s.indexOf(p.start, from);
  const i1 = s.indexOf(p.endMarker, i0 + p.start.length);
  if (i0 < 0 || i1 < 0) throw Error('锚点缺失：' + p.name);
  return s.slice(i0, i1);
}
const st = strip(s688);
const olds = PATCH.patches.map(p => locate(st.text, p));
let rev = s689;
for (let i = PATCH.patches.length - 1; i >= 0; i--)
  rev = rev.replace(PATCH.patches[i].new, () => olds[i]);
rev = restore(rev, st.groups);
ck('内嵌 Lua 反向补丁逐字节还原 688', rev === s688,
   rev === s688 ? '' : Buffer.byteLength(rev) + ' vs ' + Buffer.byteLength(s688));
ck('空白行剥离数 = 12801', st.removed === 12801, st.removed);
ck('脚本体积下降', Buffer.byteLength(s689) < Buffer.byteLength(s688),
   Buffer.byteLength(s688) + ' -> ' + Buffer.byteLength(s689));

// ④ 内容闸门（689 Lua 与 688 的关卡数据/文本段逐字节同源）
const ns = (f, ks) => ks.reduce((x, k) => x.flatMap(y => (y.sub || []).filter(z => z.field === k)), [f]);
const tn = r => { const f = ns(r.field, [505, 503, 75, 510, 501])[0]; return f?.payload?.toString('utf8') ?? null; };
const DATA = JSON.parse(fs.readFileSync(path.join(REPO, '688_第4至7关接入/688_关卡数据.json'), 'utf8'));
let textBad = [];
for (const item of DATA.levels)
  for (const t of item.texts)
    for (const [slot, val] of [['letter', t.letter], ['who', t.who], ['what', t.what]]) {
      const r = g689.recs.find(x => x.name === `${slot}.${item.level}.${t.slot}`);
      if (!r || tn(r) !== val) textBad.push(`${slot}.${item.level}.${t.slot}`);
    }
ck('静态文本 75 处逐条一致', textBad.length === 0, textBad.slice(0, 6));
let oldBad = [];
for (const lv of [1, 2, 3])
  for (let i = 1; i <= (lv === 1 ? 5 : 6); i++)
    for (const s of ['who', 'letter', 'what']) {
      const x = g688.recs.find(r => r.name === `${s}.${lv}.${i}`);
      const y = g689.recs.find(r => r.name === `${s}.${lv}.${i}`);
      if (x && y && tn(x) !== tn(y)) oldBad.push(`${s}.${lv}.${i}`);
    }
ck('前 3 关静态文本零改动', oldBad.length === 0, oldBad.slice(0, 6));
ck('689 注册 7 关', ['001','002','003','004','005','006','007']
  .every(x => s689.includes(`__M["levels.case_${x}"]`)));
ck('689 无未注册线索类型', !/above_any|below_any|left_any|right_any/.test(s689));
ck('685 每帧抬层不变式保留', s689.includes('self:_mark_layer_raise()') &&
   s689.includes('function Adapter:_mark_layer_raise()'));
ck('687 SETTLE_ART_TINT 20 层未改', (s689.match(/\{\s*"art647\./g) || []).length === 20);

// ⑤ luac -p
const TMP = os.tmpdir();
for (const [tag, src] of [['688', s688], ['689', s689]]) {
  const f = `_wb689_syn_${tag}.lua`;
  fs.writeFileSync(path.join(TMP, f), src, 'utf8');
  try { execFileSync('luac.exe', ['-p', f], { cwd: TMP }); ck(`luac -p ${tag}`, true, ''); }
  catch (e) { ck(`luac -p ${tag}`, false, String(e.message).slice(0, 120)); }
}

const pass = checks.filter(c => c.ok).length;
const out = { timestamp: new Date().toISOString(), checks: checks.length, pass,
  fail: checks.length - pass, verdict: pass === checks.length,
  baseSha688: sha(P688), outSha689: sha(P689), details: checks };
fs.writeFileSync(path.join(DIR, '689_结构校验.json'), JSON.stringify(out, null, 2));
console.log(JSON.stringify({ checks: out.checks, pass, fail: out.fail, verdict: out.verdict }, null, 2));
if (!out.verdict) process.exit(1);
