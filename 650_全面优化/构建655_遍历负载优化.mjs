// 655：基于 654_退出拦截修复.gil 的遍历负载优化构建器（只改内嵌 Lua，不动控件树）
//
// 审查结论（详见 655_遍历负载优化报告.md）：
//   652/653 的「父控件分类」把 1109 个静态叶移到 16 个容器下，但全树 DFS 仍要访问
//   全部叶节点并额外访问 16 个容器；离线收益主要来自 652 同时引入的精确路径表与父级门控，
//   653 相对 652 仅 -0.304%，稳态阶段反升约 0.2%。因此 655 不再新增分类容器，
//   改为消除「全树名字索引的逐帧重建」并收敛其它遍历/重复写入。
//
// 复现：node 构建655_遍历负载优化.mjs
// 依赖：本项目现有 tools/gil/gilread.mjs 与 gilwrite.mjs，无新增依赖、不联网。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import os from 'node:os';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { readGil, encodeMsg, asIdList } from '../tools/gil/gilread.mjs';
import { writeGil, findScriptLeaf } from '../tools/gil/gilwrite.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const INPUT = path.join(HERE, '654_退出拦截修复.gil');
const OUTPUT = path.join(HERE, '655_遍历负载优化.gil');
const LUA = path.join(HERE, '655_遍历负载优化.lua');
const AUDIT = path.join(HERE, '655_遍历负载优化审计.json');
const INPUT_SHA = 'fd8b3e7d422f5fa626b103e5cf993fad68bdb926d8e84e6bb70f44dc4d8f68d3';
const hash = b => crypto.createHash('sha256').update(b).digest('hex');

const original = readGil(INPUT);
assert.equal(hash(original.src), INPUT_SHA, '输入不是已审计的 654_退出拦截修复.gil');
const g = readGil(INPUT);
const byId = new Map(g.recs.map(r => [Number(r.id), r]));
const kids = r => r.childList ? (asIdList(r.childList.payload, true) || []).map(Number) : [];
const root = g.recs.find(r => r.name === 'root');
assert(root, '缺少 root');

// ── 1. 生成扩充后的精确路径表 ────────────────────────────────────────────────
// 候选 = 脚本里出现过的名字字面量 ∪ 字符串拼接前缀对应的静态控件名 ∪ root 直系
//       ∪ 项目既有的教程页/素材行命名段。只收运行时 root 子树中全局唯一命名、
//       且路径每一段在父级子列表中都无重名的控件，避免 GetChild 取错分支。
const script0 = findScriptLeaf(original).buf.toString('utf8');
const oldBlock = script0.slice(script0.indexOf('local STATIC_PATH_653 = {'), script0.indexOf('local function path_lookup_653'));
const oldRoutes = [...oldBlock.matchAll(/\[\s*"([^"]+)"\s*\]\s*=\s*\{/g)].map(m => m[1]);
const literal = new Set();
for (const m of script0.matchAll(/["']([A-Za-z][A-Za-z0-9_.\-]{1,80})["']/g)) literal.add(m[1]);
const concatPrefixes = new Set();
for (const m of script0.matchAll(/["']([A-Za-z][A-Za-z0-9_.\-]*\.)["']\s*\.\./g)) concatPrefixes.add(m[1]);
// 只补「功能性命名段」：格子/地毯、标签、弹窗、遮罩、卡片、素材行、提示。
// 不把 art641/art642/td.page 内部的静态美术叶整批塞进表 —— 它们从不被按名查找，
// 却会新增数千个字符串常量，扰动 Lua 短字符串哈希表布局并放大加载体积。
const extraPrefix = /^(cell\.|floor\.cell\.|label\.|modal\.level\.|block640\.|hint635\.|select\.card\.|row\.|clues\.|hex\.|hit\.|fart\.|tpl)/;

const runtime = [];
const nameCount = new Map();
const childNameCount = new Map();
function collect(r, p, unambiguous) {
  const pp = [...p, r.name || ''];
  runtime.push({ rec: r, path: pp, unambiguous });
  if (r.name) nameCount.set(r.name, (nameCount.get(r.name) || 0) + 1);
  const cnt = new Map();
  for (const id of kids(r)) {
    const nm = byId.get(id)?.name || '';
    cnt.set(nm, (cnt.get(nm) || 0) + 1);
  }
  childNameCount.set(Number(r.id), cnt);
  for (const id of kids(r)) {
    const c = byId.get(id);
    const seg = c?.name || '';
    const okSeg = seg !== '' && cnt.get(seg) === 1;
    collect(c, pp, unambiguous && okSeg);
  }
}
collect(root, [], true);

const candidates = new Set();
for (const nm of oldRoutes) candidates.add(nm); // 652/653 原有条目必须保留
for (const { rec } of runtime) {
  const nm = rec.name;
  if (!nm || nameCount.get(nm) !== 1) continue;
  if (literal.has(nm) || extraPrefix.test(nm)) candidates.add(nm);
  else {
    // 仅当拼接前缀属于功能性命名段时才纳入，避免把美术叶整批塞进表。
    for (const p of concatPrefixes) {
      if (nm.startsWith(p) && extraPrefix.test(p)) { candidates.add(nm); break; }
    }
  }
}
for (const id of kids(root)) {
  const nm = byId.get(id)?.name;
  if (nm && nameCount.get(nm) === 1) candidates.add(nm);
}
const routes = new Map();
for (const { rec, path: p, unambiguous } of runtime) {
  const nm = rec.name;
  if (!nm || !candidates.has(nm) || nameCount.get(nm) !== 1 || nm.includes('/')) continue;
  if (!unambiguous) continue;
  routes.set(nm, p.join('/'));
}
for (const nm of oldRoutes) assert(routes.has(nm), '原有精确路径丢失: ' + nm);
assert(routes.size > oldRoutes.length, '路径表没有扩充');

// ── 2. 脚本补丁 ─────────────────────────────────────────────────────────────
let script = script0;
const patches = [];
function replaceOnce(tag, oldText, newText) {
  const parts = script.split(oldText);
  assert.equal(parts.length, 2, `替换不唯一 [${tag}]: 命中 ${parts.length - 1} 次`);
  script = parts[0] + newText + parts[1];
  patches.push(tag);
}
const q = s => JSON.stringify(s);
const routeLua = 'local STATIC_PATH_655 = {\n' +
  [...routes.entries()].map(([nm, p]) => '  [' + q(nm) + '] = ' + q(p) + ',').join('\n') +
  '\n}\n' + `local function path_lookup_655(roots, name)
  local route = STATIC_PATH_655[name]
  if route == nil then return nil end
  -- 首次使用时把紧凑字符串路径拆成数组并回写，后续查找不再解析。
  if type(route) == "string" then
    local parts = {}
    for seg in route:gmatch("[^/]+") do parts[#parts + 1] = seg end
    STATIC_PATH_655[name] = parts
    route = parts
  end
  for i = 1, #roots do
    local cur = roots[i]
    local ok, rn = pcall(function() return cur.name end)
    if ok and rn == route[1] then
      for k = 2, #route do
        local parent = cur
        local good, child = pcall(function() return parent:GetChild(route[k]) end)
        if not good or child == nil then cur = nil; break end
        cur = child
      end
      if cur ~= nil then
        local good, actual = pcall(function() return cur.name end)
        if good and actual == name then return cur end
      end
    end
  end
  return nil
end
`;
// 2.1 整块替换 653 的静态路径表与查找函数
{
  const start = script.indexOf('local STATIC_PATH_653 = {');
  const end = script.indexOf('function Adapter:_build_name_index', start);
  assert(start > 0 && end > start, '找不到 653 路径表边界');
  script = script.slice(0, start) + routeLua + '\n' + script.slice(end);
  patches.push('static_route_table');
}
script = script.replaceAll('path_lookup_653', 'path_lookup_655');
patches.push('path_lookup_callsite');

// 2.2 名字索引不再逐帧作废：结构代数变化立即重建，否则每 1.0s 复核一次。
replaceOnce('index_build_stamp',
  '  self._name_idx_clock = self.clock',
  '  self._name_idx_at = self.clock');
replaceOnce('index_stale_rule',
  '  if idx == nil or self._name_idx_gen ~= self._lookup_gen or self._name_idx_clock ~= self.clock then',
  `  -- 655: 结构代数变化立即重建；同一代数内最多每 1.0 秒复核一次，
  -- 既消除逐帧全树 DFS，又保留客户端迟到控件/自行重建的自愈能力。
  local stale = idx == nil or self._name_idx_gen ~= self._lookup_gen
    or self._name_idx_at == nil or (self.clock - self._name_idx_at) >= 1.0
  if stale then`);

// 2.3 Controller 的独立全树 DFS 先复用 adapter 的路径/索引与缓存
replaceOnce('controller_find_by_name',
  'function Controller:_find_by_name(name)\n  if name == nil then return nil end\n  local hit = nil\n  local search = nil',
  `function Controller:_find_by_name(name)
  if name == nil then return nil end
  local hit = nil
  -- 655: 先复用 adapter 的精确路径/名字索引与缓存，避免另起一趟全树 DFS。
  if self.adapter ~= nil and self.adapter.find ~= nil then
    pcall(function() hit = self.adapter:find(name) end)
    if hit ~= nil then return hit end
  end
  local search = nil`);

// 2.4 assets 是静态容器：按查找代数缓存映射，回读句柄名称确认有效性
replaceOnce('palette_cache_read',
  'function Controller:_palette_assets_map()\n  local assets = nil',
  `function Controller:_palette_assets_map()
  -- 655: assets 子树为静态，按查找代数缓存；句柄失效（客户端重建）时自动重建。
  local _ad655 = self.adapter
  local _gen655 = _ad655 and (_ad655._lookup_gen or 0) or -1
  local _cache655 = self._palette_assets_cache655
  if _cache655 ~= nil and _cache655.gen == _gen655 then
    local _ok655, _nm655 = pcall(function() return _cache655.assets.name end)
    if _ok655 and _nm655 == "assets" then return _cache655.map end
  end
  local assets = nil`);
replaceOnce('palette_cache_write',
  '    if nm ~= nil then map[nm] = ks[i] end\n  end\n  return map\nend',
  '    if nm ~= nil then map[nm] = ks[i] end\n  end\n  self._palette_assets_cache655 = { gen = _gen655, assets = assets, map = map }\n  return map\nend');

// 2.5 装饰颜色写：句柄 + 目标值 + 代数三重缓存，句柄变化必然重放
replaceOnce('art_color_guard',
  `local function write_art_color650(c, key, want)
  if c == nil then return end
  local actual = nil
  pcall(function() actual = c[key] end)
  if actual ~= want then pcall(function() c[key] = want end) end
end`,
  `local art_color_cache655 = setmetatable({}, { __mode = "k" })
local art_color_gen655 = -1
local function write_art_color650(c, key, want)
  if c == nil then return end
  local gen = (adapter and adapter._lookup_gen) or 0
  if art_color_gen655 ~= gen then
    art_color_cache655 = setmetatable({}, { __mode = "k" })
    art_color_gen655 = gen
  end
  local slot = art_color_cache655[c]
  if slot == nil then slot = {}; art_color_cache655[c] = slot end
  if slot[key] == want then return end
  local actual = nil
  pcall(function() actual = c[key] end)
  if actual ~= want then pcall(function() c[key] = want end) end
  slot[key] = want
end`);

// 2.6 射线补扫：诊断日志用的 .name 回读延迟到真正要写样本时，
//     不改 seen/set/idle/停止条件，也不跳过任何节点或属性检查。
replaceOnce('raycast_lazy_name_read',
  '    local nm = "?"\n    pcall(function() nm = tostring(c.name) end)\n',
  '');
replaceOnce('raycast_lazy_sample',
  '          if #samples < 6 then samples[#samples + 1] = nm .. ":" .. tostring(before) .. "->true" end',
  `          if #samples < 6 then
            local nm = "?"
            pcall(function() nm = tostring(c.name) end)
            samples[#samples + 1] = nm .. ":" .. tostring(before) .. "->true"
          end`);

// 2.7 654 新增的逐帧静音写：同一句柄只写一次，句柄变化或代数变化重新确保
replaceOnce('block640_silent_table',
  'local function sync_block640()',
  `local block640_silent655 = setmetatable({}, { __mode = "k" })
local block640_silent_gen655 = -1
local function sync_block640()`);
replaceOnce('block640_silent_write',
  '    if hit ~= nil then\n      pcall(function() if hit.clickAudioId ~= 0 then hit.clickAudioId = 0 end end)\n    end',
  `    if hit ~= nil then
      local _g655 = adapter._lookup_gen or 0
      if block640_silent_gen655 ~= _g655 then
        block640_silent655 = setmetatable({}, { __mode = "k" })
        block640_silent_gen655 = _g655
      end
      if not block640_silent655[hit] then
        pcall(function() if hit.clickAudioId ~= 0 then hit.clickAudioId = 0 end end)
        block640_silent655[hit] = true
      end
    end`);

// Lua 语法编译（写到 ASCII 临时路径，避开中文路径下 Lua 取参限制）
const tmpLua = path.join(os.tmpdir(), 'murdoku655_syntax_check.lua');
fs.writeFileSync(tmpLua, script);
const chk = spawnSync('lua', ['-e', `assert(loadfile(${JSON.stringify(tmpLua)}))`], { encoding: 'utf8' });
assert.equal(chk.status, 0, 'Lua 编译失败: ' + (chk.stderr || chk.stdout || ''));
fs.unlinkSync(tmpLua);

// ── 3. 落盘与结构断言 ───────────────────────────────────────────────────────
fs.writeFileSync(LUA, script);
const leaf = findScriptLeaf(g);
leaf.field.payload = Buffer.from(script);
leaf.field.len = leaf.field.payload.length;
leaf.field.sub = null;
const oldLeaf = findScriptLeaf(original).field;
const expectedBody = encodeMsg(g.tree);
const expectedRecs = new Map(g.recs.map(r => [Number(r.id), encodeMsg([r.field])]));

const report = writeGil(g, OUTPUT, {
  label: '655 遍历负载优化', expectRecs: original.recs.length, expectMarker: 'v635', quiet: true,
  assert: d => {
    assert.equal(d.recs.length, original.recs.length, '控件数量变化');
    assert(encodeMsg(d.tree).equals(expectedBody), '输出与定向修改结果不一致');
    assert(findScriptLeaf(d).buf.equals(Buffer.from(script)), '内嵌脚本落盘不一致');
    assert(d.trailer.equals(original.trailer), '文件尾变化');
    for (const r of d.recs) {
      const want = expectedRecs.get(Number(r.id));
      assert(want && want.equals(encodeMsg([r.field])), '控件记录变化 ' + r.name);
    }
    // 非脚本顶层字段逐字节不变
    function nonUI(ff, scriptField) {
      return ff.map(f => {
        if (f.field === 9) return null;
        function has(x) { return x === scriptField || (x.sub || []).some(has); }
        return has(f) ? null : encodeMsg([f]).toString('hex');
      });
    }
    assert.deepEqual(nonUI(original.tree, oldLeaf), nonUI(d.tree, findScriptLeaf(d).field), '非脚本顶层字段变化');
    return true;
  },
});

const audit = {
  base: path.basename(INPUT),
  inputSha256: INPUT_SHA,
  output: path.basename(OUTPUT),
  outputSha256: hash(report.g2.src),
  inputBytes: original.src.length,
  outputBytes: report.bytes,
  scriptBytesBefore: Buffer.byteLength(script0),
  scriptBytesAfter: Buffer.byteLength(script),
  recordsBefore: original.recs.length,
  recordsAfter: report.g2.recs.length,
  controlRecordsChanged: 0,
  staticRoutes: { before: oldRoutes.length, after: routes.size, added: routes.size - oldRoutes.length, oldRoutesPreserved: true },
  runtimeTreeNodes: runtime.length,
  candidateNames: candidates.size,
  concatPrefixes: [...concatPrefixes].sort(),
  patches,
  checks: {
    diskReread: true, roundtrip: true, expectedBodyExact: true, luaCompile: true,
    allControlRecordsByteIdentical: true, nonScriptTopFieldsByteIdentical: true,
    trailerUnchanged: true, scriptEqualsDeliveredLua: true,
  },
  designNotes: [
    '不再新增分类父级：655 的控件树与 654 完全一致，避免增加 DFS 节点与重挂风险。',
    '精确路径表由存档自动生成，覆盖脚本字面量名、字符串拼接前缀名、root 直系与既有教程/素材段。',
    '名字索引失效由「逐帧」改为「结构代数 + 1.0 秒复核」，保留迟到控件自愈与 name 回读校验。',
    '属性写入缓存以弱键表按句柄失效，句柄变化或查找代数变化必然重放，不做无条件的跨帧记忆。',
  ],
  limitations: [
    '离线调用次数不是实机帧率/CPU/显存，不能换算成百分比性能提升。',
    'Lua 语法编译在 Lua 5.4 二进制上完成；未找到 5.3 可执行文件，补丁未使用 5.4 专属语法。',
    '静态路径表增大了脚本体积，启动时的表构造成本需实机量测。',
    '未做实机导入、截图、点击命中与听感验收。',
  ],
};
fs.writeFileSync(AUDIT, JSON.stringify(audit, null, 2));
console.log(JSON.stringify(audit, null, 2));
