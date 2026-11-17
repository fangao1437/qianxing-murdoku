// 687 · 结构闸门 + Lua 行为级模拟 + 官方闸门
//   ① 686→687 记录表 7826→7826，旧记录改动严格 7 条白名单（rogue=0）
//   ② 48 个共享网格纸静态层逐字节不变；home/game 分屏靠 Lua 覆盖
//   ③ 内嵌 Lua 两处补丁可反向逐字节还原 686；源码同步；luac -p 四份
//   ④ 行为模拟：lua.exe 真跑「enabled 染色分支」与「sync_art641 父坐标片段」
//   ⑤ roundtrip / check_childlist_top
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(url(path.join(REPO, 'tools/gil/gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(REPO, 'tools/gil/gilwrite.mjs')));
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '687_规格.json'), 'utf8'));
const A = path.join(REPO, SPEC.base.file);
const B = path.join(DIR, '687_综合整改.gil');
const ga = readGil(A), gb = readGil(B);
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const checks = [];
const ck = (name, ok, detail) => { checks.push({ name, ok: !!ok, detail }); if (!ok) console.log('  FAIL', name, detail ?? ''); };

const ba = new Map(ga.recs.map(r => [r.id, encodeMsg([r.field])]));
const bb = new Map(gb.recs.map(r => [r.id, encodeMsg([r.field])]));
const byIdA = new Map(ga.recs.map(r => [r.id, r])), byIdB = new Map(gb.recs.map(r => [r.id, r]));
const byNameA = new Map(ga.recs.filter(r => r.name).map(r => [r.name, r]));
const byNameB = new Map(gb.recs.filter(r => r.name).map(r => [r.name, r]));
const R = n => byNameB.get(n);
const added = [...bb.keys()].filter(id => !ba.has(id));
const removed = [...ba.keys()].filter(id => !bb.has(id));
const changed = [...ba.keys()].filter(id => bb.has(id) && !ba.get(id).equals(bb.get(id)));
const geo = r => { const st = stateBlocks(r.field.sub, [])[0], p = pairOf(st, 504), s = pairOf(st, 505);
  return [pairValue(p, 0), pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)]; };
const close = (a, b, t = 1e-4) => Math.abs(a - b) < t;

// ── ① 记录表 ────────────────────────────────────────────────────────────
ck('记录数 7826→7826', ga.recs.length === 7826 && gb.recs.length === 7826, [ga.recs.length, gb.recs.length]);
ck('0 新增 / 0 删除', added.length === 0 && removed.length === 0, [added.length, removed.length]);
const allowed = new Set(SPEC.D_close.scope.map(n => R(n)?.id));
allowed.add(R(SPEC.A_countdown.name)?.id);
const rogue = changed.filter(id => !allowed.has(id));
ck('旧记录改动恰好 7 条且全部在白名单（rogue=0）', changed.length === 7 && rogue.length === 0,
  { changed: changed.length, rogue: rogue.map(id => byIdB.get(id)?.name) });
ck('686 SHA 与规格一致', sha(A) === SPEC.base.sha256);
// 所有父级 childList 与 recTop 同序
const rt = gb.tree.find(f => f.field === 9);
const ord = new Map(); rt.sub.forEach((f, i) => ord.set(f, i));
let orderOk = true, bad = '';
for (const r of gb.recs) {
  const cl = findChildListTop(r.field.sub || []);
  const ids = cl ? (asIdList(cl.payload, true) || []) : [];
  const seq = ids.map(id => ord.get(byIdB.get(id)?.field) ?? -1);
  if (seq.some((v, i) => i > 0 && v < seq[i - 1])) { orderOk = false; bad = r.name; break; }
}
ck('所有父级 childList 与 recTop 同序', orderOk, bad);
const dangling686 = new Set([...ba.keys()].filter(id =>
  byIdA.get(id).parentId != null && !byIdA.has(byIdA.get(id).parentId)));
const danglingNew = [...bb.keys()].filter(id =>
  byIdB.get(id).parentId != null && !bb.has(byIdB.get(id).parentId) && !dangling686.has(id));
ck('新增悬空父引用 0（686 基线悬空原样保留）', danglingNew.length === 0,
  { baseline: dangling686.size, added: danglingNew.length });

// ── ② A 倒计时 ──────────────────────────────────────────────────────────
ck('退出菜单倒计时 -200 → -95（跟随 683 四键换位）',
  close(geo(R(SPEC.A_countdown.name))[1], SPEC.A_countdown.toY), geo(R(SPEC.A_countdown.name)));
for (const st of stateBlocks(R(SPEC.A_countdown.name).field.sub, []))
  if (!close(pairValue(pairOf(st, 504), 1), -95)) { ck('倒计时 4 个状态全部 -95', false); break; }
ck('倒计时 4 个状态全部 -95', stateBlocks(R(SPEC.A_countdown.name).field.sub, [])
  .every(st => close(pairValue(pairOf(st, 504), 1), -95)));
ck('result.settle.countdown 仍 -258（684 已换位）', close(geo(R('result.settle.countdown'))[1], -258));
ck('settle.btn.countdown 仍 -339（结算按钮从未换位）', close(geo(R('settle.btn.countdown'))[1], -339));
ck('退出菜单四键 y=120/40/-40/-120 未动',
  ['modal.exit', 'modal.save', 'modal.settle', 'modal.cancel']
    .every((n, i) => close(geo(R(n))[1], [120, 40, -40, -120][i])));
ck('cancel.settle_shift=30 的让位逻辑仍在',
  findScriptLeaf(gb).buf.toString('utf8').includes('cancel.settle_shift = (self:settle_seconds_left() > 0) and 30 or 0'));

// ── ② C 网格纸 ──────────────────────────────────────────────────────────
const reuse = R('art657.grid.reuse');
const kids = gb.recs.filter(r => r.parentId === reuse.id);
ck('网格纸共享子层 48 个', kids.length === 48, kids.length);
ck('网格纸父层 + 48 子层逐字节不变',
  ba.get(reuse.id).equals(bb.get(reuse.id)) && kids.every(k => ba.get(k.id).equals(bb.get(k.id))));
ck('656 设计位 -5 / 680 后 -45.5 口径：静态层保持 686（-45.5）',
  close(geo(R('art656.home.grid.paper'))[1], -45.5));
ck('首页其它元素（卡片/教程圆按钮/便签）零改动',
  ['art641.home', 'art656.home.paper', 'td.home.page.1', 'art647.home.settle.yellow']
    .filter(n => R(n)).every(n => ba.get(R(n).id).equals(bb.get(R(n).id))));
ck('SETTLE_ART_TINT 20 层静态颜色未改',
  gb.recs.filter(r => /^art647\.(home|select)\.settle\./.test(r.name || ''))
    .every(r => ba.get(r.id).equals(bb.get(r.id))));
ck('684/685/686 成果层未改（放大镜/X 标记/教程五卡）',
  gb.recs.filter(r => /^art684\.|^art685\.mark\.|^td\.home\.page\.1\.rule\./.test(r.name || ''))
    .every(r => ba.get(r.id).equals(bb.get(r.id))));

// ── ② D 小叉 ────────────────────────────────────────────────────────────
for (const n of ['hint635.menu.close', 'hint635.result.close', 'help617.close',
  'td.home.closex', 'td.l1.closex', 'td.l2.closex']) {
  const [, , w, h] = geo(R(n));
  ck('所有弹窗小叉 20×20：' + n, close(w, 20) && close(h, 20), [w, h]);
}
for (const n of ['hint635.menu.close.hit', 'hint635.result.close.hit', 'help617.close.hit']) {
  const [, , w, h] = geo(R(n));
  ck('提示/帮助弹窗热区仍 36×36：' + n, close(w, 36) && close(h, 36));
}
for (const n of ['td.home.btn.close', 'td.l1.btn.close', 'td.l2.btn.close']) {
  const [, , w, h] = geo(R(n));
  ck('教程热区同步放大到 ≈46.10229：' + n, close(w, SPEC.D_close.hitTo) && close(h, SPEC.D_close.hitTo), [w, h]);
}
const drift = ['home', 'l1', 'l2'].map(p => {
  const n = 'td.' + p + '.closex', a = byNameA.get(n), b = R(n);
  if (!a || !b) return { n, ok: false, why: 'missing', a: !!a, b: !!b };
  const ga0 = geo(a), gb0 = geo(b);
  return { n, ok: close(gb0[0], ga0[0]) && close(gb0[1], ga0[1]),
    from: ga0.slice(0, 2), to: gb0.slice(0, 2) };
});
ck('小叉中心位置未漂移', drift.every(d => d.ok), drift);
ck('无小叉弹窗未新增关闭控件', !gb.recs.some(r => /^(modal|result|win)\..*close/i.test(r.name || '') && !ba.has(r.id)));
// 颜色 / 图元未动（只改 505 尺寸）
const imgOf = f => {
  const ns = (fld, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [fld]);
  const p = ns(f, [505, 503, 84])[0];
  if (!p) return null;
  const num = k => { const q = p.sub.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
  return [num(502), num(503), num(504)];
};
ck('小叉颜色 #FF47271A / 图元 100151 / 染色开关保持 686',
  ['td.home.closex', 'td.l1.closex', 'td.l2.closex'].every(n => {
    const a = imgOf(byNameA.get(n).field), b = imgOf(R(n).field);
    return a && b && JSON.stringify(a) === JSON.stringify(b) && a[1] === 100151 && a[0] === 0xFF47271A;
  }));

// ── ③ 内嵌 Lua ──────────────────────────────────────────────────────────
const sa = findScriptLeaf(ga).buf.toString('utf8'), sb = findScriptLeaf(gb).buf.toString('utf8');
ck('内嵌 Lua 644,453 → 645,926 B', Buffer.byteLength(sa) === 644453 && Buffer.byteLength(sb) === 645926,
  [Buffer.byteLength(sa), Buffer.byteLength(sb)]);
const needles = {
  tintArt: 'local art = self:sub(id, "art")',
  tintGray: 'k.imageColor = value and (outline and 0xFF6C402E or 0xFFFCECD4) or 0xFF686B70',
  tintOriginBg: 'if bg then bg.imageColor = value and 0xFFFFFFFF or 0xFF686B70 end',
  gridHomeDy: 'local dx, dy = 0, 40.5',
  gridGameUnchanged: 'if screen == "game" then dx, dy = 105, 46 end',
  legacyMark: 'function Adapter:_mark_hide_all()',
  legacyTint: 'local SETTLE_ART_TINT = {',
  legacyShift: 'if key == "settle_shift" then',
};
for (const [k, v] of Object.entries(needles)) ck('Lua 补丁/保留 ' + k, sb.includes(v));
// 反向还原：把 687 两处补丁的 to 换回 from（与构建器同源）
const P_B_FROM = `  elseif key == "enabled" then
    if ctrl.interactable ~= nil then ctrl.interactable = value and true or false end
    if id == "result.settle" or id == "modal.settle" then
      local bg = self:sub(id, "bg")
      if bg then bg.imageColor = value and 0xFFFFFFFF or 0xFF686B70 end
    end`;
const P_C_FROM = `        local dx, dy = 0, 0
        if screen == "game" then dx, dy = 105, 46 end`;
const cutBetween = (s, from, to) => {
  const i = s.indexOf(from), j = s.indexOf(to, i);
  if (i < 0 || j < 0) throw Error('反向锚点缺失');
  return [s.slice(0, i), s.slice(i, j), s.slice(j)];
};
{
  // 用构建器的 P_B_TO / P_C_TO 从 687 源码文件里读回（避免重复长串）
  const build = fs.readFileSync(path.join(DIR, '构建687.mjs'), 'utf8');
  const grab = (name) => {
    const m = build.match(new RegExp('const ' + name + ' = `([\\s\\S]*?)`;'));
    if (!m) throw Error('构建器缺 ' + name);
    return m[1];
  };
  const B_TO = grab('P_B_TO'), C_TO = grab('P_C_TO');
  let rev = sb;
  ck('反向锚点各出现一次', (rev.split(B_TO).length - 1) === 1 && (rev.split(C_TO).length - 1) === 1);
  rev = rev.replace(B_TO, P_B_FROM).replace(C_TO, P_C_FROM);
  ck('内嵌 Lua 反向替换逐字节还原 686', rev === sa,
    rev === sa ? 'OK' : '差 ' + (Buffer.byteLength(rev) - Buffer.byteLength(sa)) + ' B');
}
// 源码同步
const srcA = fs.readFileSync(path.join(REPO, 'lua/engine_adapter_qianxing.lua'), 'utf8');
const srcB = fs.readFileSync(path.join(REPO, 'lua/entry_client_script.lua'), 'utf8');
ck('源码 adapter 含 687 染色分支', srcA.includes('★ 687') && srcA.includes('0xFF686B70'));
ck('源码 entry 含 687 网格纸双屏注释', srcB.includes('★ 687 网格纸双屏分开'));
// luac -p 四份
const LUAC = 'C:/Users/18182/AppData/Lua/bin/luac.exe';
const LUAC2 = 'C:/Users/18182/AppData/Local/Programs/Lua/bin/luac.exe';
const luac = fs.existsSync(LUAC) ? LUAC : LUAC2;
const luaFiles = [path.join(DIR, '687_内嵌Lua_686.lua'), path.join(DIR, '687_内嵌Lua_687.lua'),
  path.join(REPO, 'lua/engine_adapter_qianxing.lua'), path.join(REPO, 'lua/entry_client_script.lua')];
let luacOk = true, luacErr = '';
for (const f of luaFiles) {
  try { execFileSync(luac, ['-p', f], { stdio: 'pipe' }); }
  catch (e) { luacOk = false; luacErr = path.basename(f) + ': ' + String(e.stderr || e.message).slice(0, 200); break; }
}
ck('luac -p 四份 Lua 全过', luacOk, luacErr);

// ── ④ Lua 行为级模拟 ────────────────────────────────────────────────────
const LUA = 'C:/Users/18182/AppData/Local/Programs/Lua/bin/lua.exe';
// 模拟 1：真跑 enabled 分支（6 层胶囊/描边）
function enabledBody(s) {
  const i = s.indexOf('  elseif key == "enabled" then');
  const j = s.indexOf('  elseif key == "rect" and self.apply_rect then', i);
  if (i < 0 || j < 0) throw Error('enabled 分支锚点缺失');
  return s.slice(i, j).replace('  elseif key == "enabled" then', '  if key == "enabled" then').trimEnd() + '\n  end\n';
}
function simEnabled(s) {
  return `
local kids = {}
local function mk(n) return { name=n, imageColor=0xFF123456 } end
for _, q in ipairs({"art683.modal.settle.outline.body","art683.modal.settle.outline.left",
  "art683.modal.settle.outline.right","art682.modal.settle.capsule.body",
  "art682.modal.settle.capsule.left","art682.modal.settle.capsule.right"}) do
  kids[#kids+1] = mk(q)
end
local art = { GetChildren=function(self) return kids end }
local self = { sub=function(self,id,child) if child=="art" then return art end return nil end }
local ctrl = { interactable=true }
local function run_enabled(self, ctrl, id, key, value)
${enabledBody(s)}
end
local function count(want, outlineOnly)
  local n = 0
  for _, k in ipairs(kids) do
    local isOutline = k.name:find("outline") ~= nil
    if (not outlineOnly or isOutline) and k.imageColor == want then n = n + 1 end
  end
  return n
end
run_enabled(self, ctrl, "modal.settle", "enabled", false)
local gray = count(0xFF686B70, false)
run_enabled(self, ctrl, "modal.settle", "enabled", true)
local outline = count(0xFF6C402E, true)
local capsule = count(0xFFFCECD4, false)
print(string.format('%d %d %d', gray, outline, capsule))
`;
}
// 模拟 2：真跑 sync_art641 里父坐标片段
function gridBody(s) {
  const i = s.indexOf('        -- ★ 687');
  const start = i >= 0 ? i : s.indexOf('        local dx, dy = 0, 0');
  const j = s.indexOf('        pcall(function() gp:SetAnchoredPosition(dx, dy) end)', start);
  if (start < 0 || j < 0) throw Error('网格纸片段锚点缺失');
  return s.slice(start, j + '        pcall(function() gp:SetAnchoredPosition(dx, dy) end)'.length);
}
function simGrid(s) {
  return `
local calls = {}
local gp = { SetAnchoredPosition=function(self,x,y) calls[#calls+1]={x,y} end }
local function help_visible(c, v) end
local function run(screen)
${gridBody(s)}
end
run("home"); run("game"); run("home")
for i = 1, #calls do print(string.format('%d %.1f %.1f', i, calls[i][1], calls[i][2])) end
`;
}
const fE6 = path.join(DIR, '_模拟染色686.lua'), fE7 = path.join(DIR, '_模拟染色687.lua');
const fG6 = path.join(DIR, '_模拟网格686.lua'), fG7 = path.join(DIR, '_模拟网格687.lua');
fs.writeFileSync(fE6, simEnabled(sa), 'utf8'); fs.writeFileSync(fE7, simEnabled(sb), 'utf8');
fs.writeFileSync(fG6, simGrid(sa), 'utf8'); fs.writeFileSync(fG7, simGrid(sb), 'utf8');
const nums = t => t.trim().split(/\s+/).map(Number);
const e686 = nums(execFileSync(LUA, [fE6], { encoding: 'utf8' }));
const e687 = nums(execFileSync(LUA, [fE7], { encoding: 'utf8' }));
const g686 = execFileSync(LUA, [fG6], { encoding: 'utf8' }).trim().split('\n').map(l => nums(l).slice(1));
const g687 = execFileSync(LUA, [fG7], { encoding: 'utf8' }).trim().split('\n').map(l => nums(l).slice(1));
const sim = {
  tint: { v686: { gray: e686[0], outline: e686[1], capsule: e686[2] },
    v687: { gray: e687[0], outline: e687[1], capsule: e687[2] } },
  grid: { v686: g686, v687: g687 },
};
fs.writeFileSync(path.join(DIR, '687_行为模拟.json'), JSON.stringify(sim, null, 2));
ck('686 模拟复现：未启用结算时 0 层被染灰', sim.tint.v686.gray === 0, sim.tint.v686);
ck('687 未启用结算时 6 层全部染灰 #686B70', sim.tint.v687.gray === 6, sim.tint.v687);
ck('687 启用结算时 3 层描边 #6C402E + 3 层胶囊 #FCECD4 复原',
  sim.tint.v687.outline === 3 && sim.tint.v687.capsule === 3, sim.tint.v687);
ck('686 网格纸父坐标 home=(0,0) / game=(105,46)',
  JSON.stringify(sim.grid.v686) === JSON.stringify([[0, 0], [105, 46], [0, 0]]), sim.grid.v686);
ck('687 首页回设计位 home=(0,40.5)，game 仍 (105,46)',
  JSON.stringify(sim.grid.v687) === JSON.stringify([[0, 40.5], [105, 46], [0, 40.5]]), sim.grid.v687);

// ── ⑤ 官方闸门 ──────────────────────────────────────────────────────────
let rtOk = false, clOk = false, rtErr = '', clErr = '';
try { const o = execFileSync(process.execPath, [path.join(REPO, 'tools/gil/roundtrip.mjs'), B], { encoding: 'utf8' });
  rtOk = /成功|一致|OK|pass/i.test(o); rtErr = o.slice(-200); } catch (e) { rtErr = String(e.message).slice(0, 200); }
try { const o = execFileSync(process.execPath, [path.join(REPO, 'tools/gil/check_childlist_top.mjs'), B], { encoding: 'utf8' });
  clOk = !/FAIL|Error|不一致/.test(o); clErr = o.slice(-200); } catch (e) { clErr = String(e.message).slice(0, 200); }
ck('roundtrip 逐字节往返', rtOk, rtErr);
ck('check_childlist_top 通过', clOk, clErr);

// ── 汇总 ────────────────────────────────────────────────────────────────
const failed = checks.filter(q => !q.ok);
const result = {
  version: 687, verdict: failed.length === 0,
  base: { file: path.basename(A), sha256: sha(A), records: ga.recs.length, scriptBytes: Buffer.byteLength(sa) },
  output: { file: path.basename(B), sha256: sha(B), bytes: fs.statSync(B).size,
    records: gb.recs.length, scriptBytes: Buffer.byteLength(sb) },
  checks, behaviorSimulation: sim,
  failed: failed.map(q => q.name),
  summary: { total: checks.length, passed: checks.length - failed.length, failed: failed.length },
};
fs.writeFileSync(path.join(DIR, '687_结构校验.json'), JSON.stringify(result, null, 2));
console.log(JSON.stringify({ verdict: result.verdict, ...result.summary, failed: result.failed,
  sha: result.output.sha256, bytes: result.output.bytes,
  scriptBytes: [Buffer.byteLength(sa), Buffer.byteLength(sb)], behaviorSimulation: sim }, null, 2));
if (failed.length) process.exitCode = 1;
