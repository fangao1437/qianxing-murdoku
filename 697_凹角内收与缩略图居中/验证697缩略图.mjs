// 697 · 选关缩略图行为级验证
//   对照 696（网格铺满、被拉伸） vs 697（正方形居中）
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const LUA = '"C:/Users/18182/AppData/Local/Programs/Lua/bin/lua"';
const F696 = path.join(DIR, '../696_凹角与选关缩略图/696_内嵌Lua_696.lua');
const F697 = path.join(DIR, '697_内嵌Lua_697.lua');

const PROBE = `
local LV = __require("levels.init")
local UI = __require("ui_controller")
local EA = __require("engine_adapter_qianxing")
local list = LV.ui_list()
local rows = {}
for i = 1, #list do
  local it = list[i]
  local gd = 0
  if type(it.room_grid) == "table" then
    for r = 1, it.size.rows do
      if type(it.room_grid[r]) == "table" then
        for c = 1, it.size.cols do
          if tonumber(it.room_grid[r][c]) then gd = gd + 1 end
        end
      end
    end
  end
  rows[#rows+1] = table.concat({ it.id, tostring(gd),
    tostring(it.size.rows * it.size.cols),
    tostring(#(it.walls or {})), tostring(#(it.doors or {})) }, ",")
end
print("LIST:" .. table.concat(rows, ";"))
local nodes = {}
local function push(n) nodes[#nodes+1] = n end
local it = list[7]
UI.Controller:push_room_thumb(push, "select.card.1", it,
  { x = 250, y = 330, w = 279, h = 388.8 }, "select")
local cells, walls, doors, hiddenRooms, furn, tinted = 0, 0, 0, 0, 0, 0
local minx, maxx, miny, maxy = 1e9, -1e9, 1e9, -1e9
for _, n in ipairs(nodes) do
  if n.id:find("%.cell%.") then
    cells = cells + 1
    if type(n.tint) == "table" then tinted = tinted + 1 end
    minx = math.min(minx, n.rect.x); maxx = math.max(maxx, n.rect.x + n.rect.w)
    miny = math.min(miny, n.rect.y); maxy = math.max(maxy, n.rect.y + n.rect.h)
  end
  if n.id:find("%.wall%.") then walls = walls + 1 end
  if n.id:find("%.door%.") then doors = doors + 1 end
  if n.id:find("%.room%.") and n.visible == false then hiddenRooms = hiddenRooms + 1 end
  if n.id:find("table") or n.id:find("plant") or n.id:find("statue")
     or n.id:find("shelf") or n.id:find("chair") or n.id:find("rug") then furn = furn + 1 end
end
print("THUMB:" .. table.concat({ tostring(cells), tostring(walls), tostring(doors),
  tostring(hiddenRooms), tostring(tinted), tostring(furn), tostring(#nodes) }, ","))
print("BOX:" .. string.format("%.2f,%.2f,%.2f,%.2f", minx, maxx, miny, maxy))
local ad = setmetatable({ cfg = {} }, EA.Adapter)
print("STYLE:" .. tostring(ad:color_of_style("card.name")))
local parts = UI.Controller.level_card_parts({ opts = {} }, it)
print("PARTS:" .. tostring(parts.short) .. "|" .. tostring(parts.title) .. "|" .. tostring(parts.info))
`;
function modules(src) {
  const i = src.indexOf('local FORCE_LEVEL = nil');
  if (i < 0 || src.indexOf('local FORCE_LEVEL = nil', i + 1) >= 0) throw Error('模块段锚点异常');
  return src.slice(0, i);
}
function run(file, tag) {
  const tmp = path.join(os.tmpdir(), `gil697_thumb_${tag}_${process.pid}.lua`);
  fs.writeFileSync(tmp, modules(fs.readFileSync(file, 'utf8')) + PROBE, 'utf8');
  let out = '';
  try {
    out = execFileSync(LUA, [tmp], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
                                    shell: true, timeout: 180000 });
  } catch (e) { throw Error(tag + ' Lua 运行失败：' + String(e.stderr || e.message).slice(0, 1200)); }
  finally { fs.rmSync(tmp, { force: true }); }
  const lineOf = p => (out.split('\n').find(l => l.startsWith(p)) || '').replace(/\r/g, '').trim().slice(p.length);
  return { list: lineOf('LIST:'), thumb: lineOf('THUMB:'), box: lineOf('BOX:'),
           style: lineOf('STYLE:'), parts: lineOf('PARTS:') };
}
const A = run(F696, '696'), B = run(F697, '697');
const checks = [];
const ck = (n, ok, d) => checks.push({ name: n, pass: !!ok, detail: String(d ?? '') });
const box = s => s.split(',').map(Number);
const ab = box(A.box), bb = box(B.box);
const aW = ab[1] - ab[0], aH = ab[3] - ab[2], bW = bb[1] - bb[0], bH = bb[3] - bb[2];

// ① 696 对照：网格被拉伸铺满（宽≠高）
ck('696 对照：网格不是正方形（被拉伸铺满）', Math.abs(aW - aH) > 40, `${aW.toFixed(1)}×${aH.toFixed(1)}`);
// ② 697：正方形
ck('697 棋盘为正方形', Math.abs(bW - bH) < 1, `${bW.toFixed(2)}×${bH.toFixed(2)}`);
const area = { w: 279 * 0.861, h: 388.8 * 0.783 };
const wantSide = Math.min(area.w - 16, area.h - 16);
ck('697 边长 = min(区域宽-16, 区域高-16)', Math.abs(bW - wantSide) < 2,
   `${bW.toFixed(2)} / ${wantSide.toFixed(2)}`);
// ③ 居中：中心落在棕色 inner 的中心
const cx = (bb[0] + bb[1]) / 2, cy = (bb[2] + bb[3]) / 2;
const wantCX = 250 + 279 * 0.069 + area.w / 2;
const wantCY = 330 + 388.8 * 0.164 + area.h / 2;
ck('697 水平居中（棕色区域内）', Math.abs(cx - wantCX) < 2, `${cx.toFixed(1)} / ${wantCX.toFixed(1)}`);
ck('697 垂直居中（棕色区域内）', Math.abs(cy - wantCY) < 2, `${cy.toFixed(1)} / ${wantCY.toFixed(1)}`);
// ④ 缩略图其余口径不变
const [cells, walls, doors, hidden, tinted, furn, total] = B.thumb.split(',').map(Number);
ck('36 格 / 17 墙 / 5 门 / 6 隐藏旧块 / 64 节点',
   cells === 36 && walls === 17 && doors === 5 && hidden === 6 && total === 64,
   B.thumb);
ck('36 格全带房间底色、零家具', tinted === 36 && furn === 0, `${tinted}/${furn}`);
ck('7 关 room_grid 仍完整', B.list.split(';').filter(Boolean).length === 7
   && B.list.split(';').every(r => Number(r.split(',')[1]) === Number(r.split(',')[2])), B.list.slice(0, 90));
ck('card.name 深棕字色 / 关卡短名保持', Number(B.style) === 0xFF4A2E1C
   && B.parts.split('|')[0] === '旋转档案', `${B.style} / ${B.parts.split('|')[0]}`);

const failed = checks.filter(c => !c.pass);
const out = { version: 697, pass: checks.length - failed.length, fail: failed.length,
              total: checks.length, box696: A.box, box697: B.box,
              thumb697: B.thumb, checks };
fs.writeFileSync(path.join(DIR, '697_缩略图验证.json'), JSON.stringify(out, null, 2));
console.log(`697 缩略图行为级验证 ${out.pass}/${out.total} PASS`);
console.log('  696 BOX:', A.box, ' 697 BOX:', B.box);
console.log('  THUMB:', B.thumb);
for (const f of failed) console.log('  FAIL:', f.name, '|', f.detail);
process.exit(failed.length ? 1 : 0);
