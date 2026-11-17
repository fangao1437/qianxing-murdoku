// 691 · Lua 行为级验证：689 / 691 两份落盘内嵌 Lua 的模块段分别跑 7 关
//   验证裁门后 validate_level / 答案真假向量 / room 掩码 / 区域邻接对集合不变
//   中文路径会让 lua.exe 解析失败 ⇒ 全部写到 os.tmpdir() 的 ASCII 临时名
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const F689 = path.join(ROOT, 'qianxing-murdoku/689_性能负载优化/689_内嵌Lua_689.lua');
const F691 = path.join(DIR, '691_内嵌Lua_691.lua');

const PROBE = `

-- ── 691 行为探针 ──────────────────────────────────────────────────────────
local C = __require("murdoku_core")
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
    res[#res+1] = table.concat({
      id, tostring(v), tostring(core.rows) .. "x" .. tostring(core.cols),
      tostring(#core.clues), table.concat(tv, ""), table.concat(rs, ""),
      tostring(dn), table.concat(apl, ","),
    }, "|")
  end
end
print("BEHAVIOR:" .. table.concat(res, ";"))
`;

function modules(src, tag) {
  const i = src.indexOf('local FORCE_LEVEL = nil');
  if (i < 0) throw Error(tag + ' 找不到模块段锚点');
  if (src.indexOf('local FORCE_LEVEL = nil', i + 1) >= 0) throw Error(tag + ' 模块段锚点不唯一');
  return src.slice(0, i);
}
function run(file, tag) {
  const src = fs.readFileSync(file, 'utf8');
  const tmp = path.join(os.tmpdir(), `gil691_${tag}_${process.pid}.lua`);
  fs.writeFileSync(tmp, modules(src, tag) + PROBE, 'utf8');
  let out = '';
  try {
    out = execFileSync('lua', [tmp], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], timeout: 120000 });
  } catch (e) {
    throw Error(tag + ' Lua 运行失败：' + String(e.stderr || e.message).slice(0, 800));
  } finally { fs.rmSync(tmp, { force: true }); }
  const line = out.split('\n').find(l => l.startsWith('BEHAVIOR:'));
  if (!line) throw Error(tag + ' 未输出 BEHAVIOR：' + out.slice(0, 400));
  return line.slice(9).split(';').filter(Boolean).reduce((m, row) => {
    const [id, ...rest] = row.split('|'); m[id] = rest; return m;
  }, {});
}
const A = run(F689, 'a689'), B = run(F691, 'b691');
const checks = [];
const ck = (name, ok, detail) => checks.push({ name, pass: !!ok, detail: String(detail ?? '') });
for (const id of Object.keys(A)) {
  const a = A[id], b = B[id];
  ck(id + ' 两版都有输出', !!b, b ? 'ok' : 'missing');
  if (!b) continue;
  ck(id + ' validate_level 相同', a[0] === b[0], `${a[0]} / ${b[0]}`);
  ck(id + ' 盘面尺寸相同', a[1] === b[1], `${a[1]} / ${b[1]}`);
  ck(id + ' 线索条数相同', a[2] === b[2], `${a[2]} / ${b[2]}`);
  ck(id + ' 预设答案真假向量相同', a[3] === b[3], `${a[3]} / ${b[3]}`);
  ck(id + ' room 掩码相同', a[4] === b[4], 'ok');
  ck(id + ' 区域邻接对集合相同', a[6] === b[6], `${a[6]} / ${b[6]}`);
  if (id === 'case_006') ck('case_006 门数 9 → 5', a[5] === '9' && b[5] === '5', `${a[5]} / ${b[5]}`);
  else ck(id + ' 门数不变', a[5] === b[5], `${a[5]} / ${b[5]}`);
}
ck('第6关 7×7', B.case_006 && B.case_006[1] === '7x7', B.case_006 ? B.case_006[1] : 'missing');
const pass = checks.filter(c => c.pass).length, fail = checks.length - pass;
const report = { verdict: fail === 0, pass, fail, checks,
  note: '裁门只改 case_006 的 doors；validate_level / 答案真假向量 / room / adjacency 全部不变 ⇒ 谜题不变' };
fs.writeFileSync(path.join(DIR, '691_行为验证.json'), JSON.stringify(report, null, 2));
console.log(JSON.stringify({ verdict: report.verdict, pass, fail,
  failed: checks.filter(c => !c.pass),
  case006: { doors689: A.case_006?.[5], doors691: B.case_006?.[5],
    truth689: A.case_006?.[3], truth691: B.case_006?.[3], adjacency: B.case_006?.[6] } }, null, 2));
if (fail) process.exit(1);
