// 697 · Lua 行为级验证：真实内嵌 Lua 加载 7 关 + 直接 mock 调用地毯模板路径
//   中文路径会让 lua.exe 解析失败 ⇒ 全部写到 os.tmpdir() 的 ASCII 临时名
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const LUA = '"C:/Users/18182/AppData/Local/Programs/Lua/bin/lua"';
const F696Base = path.join(DIR, '../696_凹角与选关缩略图/696_内嵌Lua_696.lua');
const F697 = path.join(DIR, '697_内嵌Lua_697.lua');
const K = JSON.parse(fs.readFileSync(path.join(DIR, '697_关卡数据.json'), 'utf8'));
const L3 = K.level3.lua;
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '697_设计与补丁.json'), 'utf8'));

const PROBE = `
-- ── 697 行为探针 ──────────────────────────────────────────────────────
local C = __require("murdoku_core")
local F = __require("furn_art")
local res = {}
for i = 1, 7 do
  local id = "case_" .. string.format("%03d", i)
  local ok, L = pcall(__require, "levels." .. id)
  if not ok or type(L) ~= "table" then
    res[#res+1] = id .. "|MISSING"
  else
    local v = C.validate_level(L)
    local core = C.new(L)
    if L.solution then
      local ids = {}
      for who in pairs(L.solution) do ids[#ids+1] = who end
      table.sort(ids)
      for _, who in ipairs(ids) do
        local p = L.solution[who]
        pcall(function() core:select_suspect(who) end)
        pcall(function() core:hold_cell(p.r, p.c) end)
      end
    end
    local tv = {}
    for k = 1, #core.clues do
      local ok2, val = pcall(function() return core:answer_clue(k, false) end)
      tv[#tv+1] = (ok2 and val) and "1" or "0"
    end
    local rs = {}
    for r = 1, core.rows do for c = 1, core.cols do
      rs[#rs+1] = tostring(core.room[r] and core.room[r][c])
    end end
    local dn = 0
    for _ in pairs(core.door_set or {}) do dn = dn + 1 end
    local ap, apl = {}, {}
    for a, nb in pairs(core.adjacency or {}) do for b in pairs(nb) do
      ap[math.min(a,b) .. "-" .. math.max(a,b)] = true
    end end
    for k in pairs(ap) do apl[#apl+1] = k end
    table.sort(apl)
    local namesOk = true
    for _, s in ipairs(L.suspects or {}) do
      if type(s.name) ~= "string" or s.name:match("^[A-FV]") or #s.name > 12 then namesOk = false end
    end
    if type(L.victim) == "table" and type(L.victim.name) == "string" then
      if L.victim.name:match("^[A-FV]") or #L.victim.name > 12 then namesOk = false end
    end
    -- 家具布局 / 地毯 variant / 逐格 els 数
    local vm = { rows = L.size.rows, cols = L.size.cols, cells = {} }
    for r = 1, vm.rows do vm.cells[r] = {}; for c = 1, vm.cols do vm.cells[r][c] = {} end end
    local keys = {}
    for r = 1, vm.rows do keys[r] = {} end
    for _, obj in pairs(L.objects or {}) do
      for _, cell in ipairs(obj.cells or {}) do
        if keys[cell.r] then keys[cell.r][cell.c] = "obj." .. tostring(obj.kind) end
      end
    end
    local fres = F.layout(vm, keys, L.room_names)
    local cp, rugEls = {}, 0
    for _, p in ipairs(fres.pieces or {}) do
      if p.kind == "carpet" then
        cp[#cp+1] = tostring(p.variant) .. "@" .. tostring(p.anchor.r) .. "," .. tostring(p.anchor.c)
      end
    end
    for _, obj in pairs(L.objects or {}) do
      if obj.kind == "carpet" then
        for _, cell in ipairs(obj.cells or {}) do
          if fres.cell[cell.r] and fres.cell[cell.r][cell.c]
             and fres.cell[cell.r][cell.c].els then rugEls = rugEls + 1 end
        end
      end
    end
    table.sort(cp)
    -- 第3关家具清点
    local plant, shelf, statue, carpetN = 0, 0, 0, 0
    for _, obj in pairs(L.objects or {}) do
      if obj.kind == "plant" then plant = #obj.cells
      elseif obj.kind == "shelf" then shelf = #obj.cells
      elseif obj.kind == "statue" then statue = #obj.cells
      elseif obj.kind == "carpet" then carpetN = #obj.cells end
    end
    local hints = {}
    for k = 1, #core.clues do
      local h = core:clue_hint(k)
      if h then
        local t = {}
        for _, cell in ipairs(h.cells or {}) do t[#t+1] = tostring(cell.r) .. ":" .. tostring(cell.c) end
        hints[#hints+1] = tostring(h.count) .. ":" .. table.concat(t, ",")
      else hints[#hints+1] = "nil" end
    end
    res[#res+1] = table.concat({
      id, tostring(v), tostring(core.rows) .. "x" .. tostring(core.cols),
      tostring(#core.clues), table.concat(tv, ""), table.concat(rs, ""),
      tostring(dn), table.concat(apl, ","), tostring(namesOk),
      table.concat(cp, ";"), tostring(rugEls), table.concat(hints, ";"),
      plant .. "," .. shelf .. "," .. statue .. "," .. carpetN,
    }, "|")
  end
end

-- ── 关键：直接 mock 调用 _spawn_furn_tpl，证明地毯走整块模板路径 ──────
local EA = __require("engine_adapter_qianxing")
local A = EA.Adapter
local spy = {}
A._spawn_whole_rug = function(self, cell_id, ctrl, ckey, prefab, cw, ch, span, off)
  spy[#spy+1] = table.concat({ tostring(cell_id), tostring(ckey), tostring(prefab),
                               tostring(cw), tostring(ch),
                               tostring(span and span.r or 1), tostring(span and span.c or 1),
                               tostring(off and off.dx or 0), tostring(off and off.dy or 0) }, ",")
  return true
end
game = { InstantiateClientUIControl = function(prefab, parent) return {} end }
local ad = setmetatable({
  cfg = { furn_tpl_prefab = {}, cells = { gap = 4 },
          furn_tpl_canvas = {}, furn_scale_axis_by_kind = {} },
  _furn_prefabs = { rug = 101, rug_2 = 102, rug_3 = 103, rug_4 = 104, rug_5 = 105 },
  _furn_span = {}, _furn_off = {}, _furn_inst = {}, _furn_level = true,
}, A)
ad._cell_size_of = function() return 100, 100 end
ad.find = function(self, name) if name == "board.rugs" then return {} end return nil end
ad._furn_scale_layers = function() return 1, 1 end
local ctrl = { GetAnchoredPosition = function() return 0, 0 end }
local tplRes = {}
for _, nm in ipairs({"furn.rug", "furn.rug.2", "furn.rug.3", "furn.rug.4", "furn.rug.5"}) do
  local ok, r = pcall(function() return ad:_spawn_furn_tpl("cell.1.1", ctrl, nm) end)
  tplRes[#tplRes+1] = nm .. "=" .. tostring(ok) .. ":" .. tostring(r)
end
print("SPAWN:" .. table.concat(tplRes, ";"))
print("SPY:" .. table.concat(spy, ";"))
print("BEHAVIOR:" .. table.concat(res, "~"))
`;

function modules(src, tag) {
  const i = src.indexOf('local FORCE_LEVEL = nil');
  if (i < 0 || src.indexOf('local FORCE_LEVEL = nil', i + 1) >= 0)
    throw Error(tag + ' 模块段锚点异常');
  return src.slice(0, i);
}
function run(file, tag) {
  const src = fs.readFileSync(file, 'utf8');
  const tmp = path.join(os.tmpdir(), `gil697_${tag}_${process.pid}.lua`);
  fs.writeFileSync(tmp, modules(src, tag) + PROBE, 'utf8');
  let out = '';
  try {
    out = execFileSync(LUA, [tmp], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
                                    shell: true, timeout: 180000 });
  } catch (e) {
    throw Error(tag + ' Lua 运行失败：' + String(e.stderr || e.message).slice(0, 1200));
  } finally { fs.rmSync(tmp, { force: true }); }
  const line = out.split('\n').find(l => l.startsWith('BEHAVIOR:'));
  if (!line) throw Error(tag + ' 无 BEHAVIOR 输出：' + out.slice(0, 500));
  const map = {};
  for (const item of line.slice(9).split('~')) {
    const p = item.split('|');
    map[p[0]] = { id: p[0], validate: p[1], size: p[2], clues: p[3], tv: p[4],
                  room: p[5], doors: p[6], adj: p[7], names: p[8],
                  carpets: p[9], els: p[10], hints: p[11], furniture: p[12] };
  }
  const lineOf = p => (out.split('\n').find(l => l.startsWith(p)) || '').replace(/\r/g, '').trim();
  return { map, spawn: lineOf('SPAWN:').slice(6), spy: lineOf('SPY:').slice(4) };
}
const A = run(F696Base, '696'), B = run(F697, '697');
const checks = [];
const ck = (name, ok, detail) => checks.push({ name, pass: !!ok, detail: String(detail ?? '') });

// ① 7 关谜题不变量：696 → 697 全部不变
for (const lv of [1, 2, 3, 4, 5, 6, 7]) {
  const id = 'case_' + String(lv).padStart(3, '0');
  const x = A.map[id], y = B.map[id];
  ck(`${id} 两版都有输出`, !!x && !!y, 'ok');
  if (!x || !y) continue;
  for (const k of ['validate', 'size', 'clues', 'tv', 'room', 'doors', 'adj'])
    ck(`${id} ${k} 与 696 相同`, x[k] === y[k], `${x[k]} / ${y[k]}`);
  ck(`${id} who 为纯人名 ≤4 字`, y.names === 'true', y.names);
}
// ② 第3关：装饰植物删除后仍自洽
const b3 = B.map['case_003'];
ck('case_003 validate_level = true', b3.validate === 'true', b3.validate);
ck('case_003 六卡全真 111111', b3.tv === '111111', b3.tv);
ck('case_003 门数 5 不变', b3.doors === '5', b3.doors);
const hp = L3.hint_preview;
const got = (b3.hints || '').split(';');
let hintOk = 0;
for (let k = 1; k <= 6; k++) {
  const want = hp[String(k)];
  const exp = want && want.count > 0 ? `${want.count}:${want.cells.join(',')}` : 'nil';
  if (got[k - 1] === exp) hintOk++;
}
ck('case_003 浅蓝提示格逐卡一致（删植物未改提示）', hintOk === 6,
   `ok=${hintOk}/6 got=${got.slice(0, 6).join(' | ')}`);
ck('case_003 植物 1 / 书架 1 / 雕塑 1 / 地毯 3',
   b3.furniture === '1,1,1,3', b3.furniture);
// ③ 三格地毯 variant 仍在
ck('第3关 L 形地毯命中 L3a', (b3.carpets || '').includes('L3a'), b3.carpets);
ck('第7关 L 形地毯命中 L3b',
   (B.map['case_007']?.carpets || '').includes('L3b'), B.map['case_007']?.carpets);
// ④ 逐格 els 在 696/697 两版均关闭
for (const lv of [3, 4, 5, 6, 7]) {
  const id = 'case_' + String(lv).padStart(3, '0');
  ck(`${id} 逐格 rug_cell_els 已关闭`, Number(B.map[id]?.els) === 0, B.map[id]?.els);
  ck(`${id} 696 对照逐格 els 同为 0`, Number(A.map[id]?.els) === 0, A.map[id]?.els);
}
// ⑤ 关键：整块模板路径真的被调用（mock spy）
const spawnPairs = Object.fromEntries(B.spawn.split(';').filter(Boolean)
  .map(s => { const [k, v] = s.split('='); return [k, v]; }));
for (const nm of ['furn.rug', 'furn.rug.2', 'furn.rug.3', 'furn.rug.4', 'furn.rug.5'])
  ck(`${nm} 走 _spawn_whole_rug 且返回 true`, spawnPairs[nm] === 'true:true', spawnPairs[nm]);
const spyRows = B.spy.split(';').filter(Boolean);
ck('五个地毯变体均命中整块模板 spy（5 次）', spyRows.length === 5, B.spy);
for (const ckey of ['rug', 'rug_2', 'rug_3', 'rug_4', 'rug_5'])
  ck(`spy 包含 ckey=${ckey}`, spyRows.some(r => r.split(',')[1] === ckey), ckey);
// 696 对照：整块模板路径本就接通，697 必须维持
ck('696 对照：地毯模板路径已接通（spy=5）',
   (A.spy || '').split(';').filter(Boolean).length === 5 && Object.values(
     Object.fromEntries(A.spawn.split(';').filter(Boolean)
       .map(s => { const [k, v] = s.split('='); return [k, v]; }))).every(v => v === 'true:true'),
   `spy=${A.spy} spawn=${A.spawn}`);
// 695 改名在 697 保持
ck('697 Lua 含 ["name"] = "誊写员"', fs.readFileSync(F697,'utf8').includes('["name"] = "誊写员"'), 'lua');
ck('697 Lua 已无「墨绿誊写」', !fs.readFileSync(F697,'utf8').includes('墨绿誊写'), 'lua');


const failed = checks.filter(c => !c.pass);
const out = { version: 697, pass: checks.length - failed.length, fail: failed.length,
              total: checks.length, spawn697: B.spawn, spy697: B.spy,
              spawn696: A.spawn, checks };
fs.writeFileSync(path.join(DIR, '697_行为验证.json'), JSON.stringify(out, null, 2));
console.log(`697 行为级验证 ${out.pass}/${out.total} PASS`);
console.log('  697 模板调用:', B.spawn);
console.log('  697 spy:', B.spy);
console.log('  696 模板调用:', A.spawn);
for (const f of failed) console.log('  FAIL:', f.name, '|', f.detail);
process.exit(failed.length ? 1 : 0);
