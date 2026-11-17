// 693 · Lua 行为级验证：691 / 693 两份落盘内嵌 Lua 的模块段分别跑 7 关
//   ① 1/2/4/5/6/7 关：validate_level / 尺寸 / 线索数 / 真假向量 / room / 邻接 / 门数逐项相同
//   ② 第3关：新设计全真关自洽 + 浅蓝提示格逐卡一致
//   ③ 三格地毯：F.layout 命中 L3a / L3b，且不再逐格双绘
//   ④ 全关姓名前缀；第4关 A/D 姓名对调但谜题不变量未变
//   中文路径会让 lua.exe 解析失败 ⇒ 全部写到 os.tmpdir() 的 ASCII 临时名
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const LUA = '"C:/Users/18182/AppData/Local/Programs/Lua/bin/lua"';
const F691 = path.join(DIR, '../691_橙黄通用卡与真机修复/691_内嵌Lua_691.lua');
const F693 = path.join(DIR, '693_内嵌Lua_693.lua');
const L3 = JSON.parse(fs.readFileSync(path.join(DIR, '693_关卡数据.json'), 'utf8')).level3.lua;
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '693_设计与补丁.json'), 'utf8'));

const PROBE = `

-- ── 693 行为探针 ──────────────────────────────────────────────────────────
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
    -- who/Lua 姓名：纯人名、≤4 字、不带字母前缀
    local namesOk = true
    local function shortName(n)
      if type(n) ~= "string" then return false end
      if n:match("^[A-Z]") then return false end
      return #n <= 12   -- 4 个汉字最多 12 字节（UTF-8）
    end
    for _, s in ipairs(L.suspects or {}) do
      if not shortName(s.name) then namesOk = false end
    end
    if type(L.victim) == "table" and not shortName(L.victim.name) then namesOk = false end
    -- 家具 F.layout / 三格地毯 variant
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
    -- 只统计地毯格位上是否仍有逐格 els（其余家具的 els 与本判据无关）
    for _, obj in pairs(L.objects or {}) do
      if obj.kind == "carpet" then
        for _, cell in ipairs(obj.cells or {}) do
          if fres.cell[cell.r] and fres.cell[cell.r][cell.c]
             and fres.cell[cell.r][cell.c].els then rugEls = rugEls + 1 end
        end
      end
    end
    table.sort(cp)
    -- 三格地毯「按边开放」探针：取 L 形第一格的内面层参数
    local bandInfo = "nil"
    for _, obj in pairs(L.objects or {}) do
      if obj.kind == "carpet" and #obj.cells == 3 then
        local pc = obj.cells[1]
        local e = fres.cell[pc.r] and fres.cell[pc.r][pc.c]
        if e and e.els and e.els[2] then
          bandInfo = string.format("%.3f,%.3f,%.3f,%.3f",
            e.els[2].w, e.els[2].h, e.els[2].dx, e.els[2].dy)
        end
      end
    end
    -- 浅蓝提示
    local hints = {}
    for k = 1, #core.clues do
      local h = core:clue_hint(k)
      if h then
        local t = {}
        for _, cell in ipairs(h.cells or {}) do
          t[#t+1] = tostring(cell.r) .. ":" .. tostring(cell.c)
        end
        hints[#hints+1] = tostring(h.count) .. ":" .. table.concat(t, ",")
      else
        hints[#hints+1] = "nil"
      end
    end
    res[#res+1] = table.concat({
      id, tostring(v), tostring(core.rows) .. "x" .. tostring(core.cols),
      tostring(#core.clues), table.concat(tv, ""), table.concat(rs, ""),
      tostring(dn), table.concat(apl, ","), tostring(namesOk),
      table.concat(cp, ";"), tostring(rugEls), table.concat(hints, ";"), bandInfo,
    }, "|")
  end
end
print("BEHAVIOR:" .. table.concat(res, "~"))
`;

function modules(src, tag) {
  const i = src.indexOf('local FORCE_LEVEL = nil');
  if (i < 0) throw Error(tag + ' 找不到模块段锚点');
  if (src.indexOf('local FORCE_LEVEL = nil', i + 1) >= 0) throw Error(tag + ' 模块段锚点不唯一');
  return src.slice(0, i);
}
function run(file, tag) {
  const src = fs.readFileSync(file, 'utf8');
  const tmp = path.join(os.tmpdir(), `gil693_${tag}_${process.pid}.lua`);
  fs.writeFileSync(tmp, modules(src, tag) + PROBE, 'utf8');
  let out = '';
  try {
    out = execFileSync(LUA, [tmp], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
                                    shell: true, timeout: 180000 });
  } catch (e) {
    throw Error(tag + ' Lua 运行失败：' + String(e.stderr || e.message).slice(0, 1200));
  } finally { fs.rmSync(tmp, { force: true }); }
  const line = out.split('\n').find(l => l.startsWith('BEHAVIOR:'));
  if (!line) throw Error(tag + ' 无 BEHAVIOR 输出：' + out.slice(0, 400));
  const map = {};
  for (const item of line.slice(9).split('~')) {
    const p = item.split('|');
    map[p[0]] = { id: p[0], validate: p[1], size: p[2], clues: p[3], tv: p[4],
                  room: p[5], doors: p[6], adj: p[7], names: p[8],
                  carpets: p[9], els: p[10], hints: p[11], band: p[12] };
  }
  return map;
}
const A = run(F691, '691'), B = run(F693, '693');
const checks = [];
const ck = (name, ok, detail) => checks.push({ name, pass: !!ok, detail: String(detail ?? '') });

// ① 回归：除第3关外，谜题不变量逐项相同
const KEYS = ['validate', 'size', 'clues', 'tv', 'room', 'doors', 'adj'];
for (const lv of [1, 2, 4, 5, 6, 7]) {
  const id = 'case_' + String(lv).padStart(3, '0');
  if (!A[id] || !B[id]) { ck(`${id} 两版都有输出`, false, 'MISSING'); continue; }
  for (const k of KEYS)
    ck(`${id} ${k} 与 691 相同`, A[id][k] === B[id][k], `${A[id][k]} / ${B[id][k]}`);
  ck(`${id} who 为纯人名 ≤4 字`, B[id].names === 'true', B[id].names);
}
// ② 第3关：新设计自洽
const b3 = B['case_003'], a3 = A['case_003'];
ck('case_003 两版都有输出', !!a3 && !!b3, 'ok');
if (a3 && b3) {
  ck('case_003 validate_level = true', b3.validate === 'true', b3.validate);
  ck('case_003 盘面 6x6 / 6 条线索', b3.size === '6x6' && b3.clues === '6', `${b3.size} ${b3.clues}`);
  ck('case_003 六卡全真 111111', b3.tv === '111111', b3.tv);
  ck('case_003 room 掩码与 691 相同', b3.room === a3.room, 'ok');
  ck('case_003 区域邻接对与 691 相同', b3.adj === a3.adj, `${a3.adj} / ${b3.adj}`);
  ck('case_003 门数 5 不变', b3.doors === '5', b3.doors);
  ck('case_003 who 为纯人名 ≤4 字', b3.names === 'true', b3.names);
  // 浅蓝提示格与 hint_preview 逐卡一致
  const hp = L3.hint_preview;
  const got = (b3.hints || '').split(';');
  let hintOk = 0;
  for (let k = 1; k <= 6; k++) {
    const want = hp[String(k)];
    const exp = want && want.count > 0 ? `${want.count}:${want.cells.join(',')}` : 'nil';
    if (got[k - 1] === exp) hintOk++;
  }
  ck('case_003 浅蓝提示格逐卡一致', hintOk === 6,
     `ok=${hintOk}/6 got=${got.slice(0, 6).join(' | ')}`);
}
// ③ 三格地毯 variant
const c3 = B['case_003']?.carpets || '', c7 = B['case_007']?.carpets || '';
ck('第3关 L 形地毯命中 L3a', c3.includes('L3a'), c3);
ck('第7关 L 形地毯命中 L3b', c7.includes('L3b'), c7);
// 693：所有地毯（含三格 L 形）都恢复逐格绘制 ⇒ 真机一定能画出来
for (const lv of [3, 4, 5, 6, 7]) {
  const id = 'case_' + String(lv).padStart(3, '0');
  ck(`${id} 地毯格位均有逐格 els`, Number(B[id]?.els) > 0, B[id]?.els);
}
// 「按边开放」：L 形第一格与右/下相邻 ⇒ 内面至少一边不内缩，w 或 h ≥ 0.90
for (const lv of [3, 7]) {
  const id = 'case_' + String(lv).padStart(3, '0');
  const parts = (B[id]?.band || '').split(',').map(Number);
  ck(`${id} 三格地毯内面按边开放（非三张单格拼接）`,
     parts.length === 4 && (parts[0] >= 0.90 || parts[1] >= 0.90), B[id]?.band);
}
// ④ 第4关 A/D 内容互换但谜题不变量未变（① 已逐项比对）
ck('第4关 A/D 姓名对调标注', SPEC.names['4'].A === '夜巡值守' &&
   SPEC.names['4'].D === '卷宗管理', `A=${SPEC.names['4'].A} D=${SPEC.names['4'].D}`);
ck('第4关声明为卡面内容顺序互换', SPEC.level4.swapType.includes('内容顺序互换'), 'ok');
ck('第4关真假向量与 691 相同', A['case_004']?.tv === B['case_004']?.tv,
   `${A['case_004']?.tv} / ${B['case_004']?.tv}`);

const pass = checks.filter(c => c.pass).length, fail = checks.length - pass;
const out = { verdict: fail === 0, pass, fail, checks,
              note: '691 vs 693 双份落盘内嵌 Lua 行为级比对 + 三格地毯 F.layout 探针' };
fs.writeFileSync(path.join(DIR, '693_行为验证.json'), JSON.stringify(out, null, 2));
for (const c of checks.filter(x => !x.pass)) console.log('FAIL:', c.name, '|', c.detail);
console.log(JSON.stringify({ verdict: out.verdict, pass, fail }, null, 2));
