// 696 · 选关缩略图行为级验证（真实内嵌 Lua 跑 ui_list / push_room_thumb / color_of_style）
//   ASCII 临时名，避免中文路径让 lua.exe 解析失败
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const LUA = '"C:/Users/18182/AppData/Local/Programs/Lua/bin/lua"';
const F695 = path.join(DIR, '../695_地毯原型注册与改名/695_内嵌Lua_695.lua');
const F696 = path.join(DIR, '696_内嵌Lua_696.lua');

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
-- 第7关缩略图节点
local nodes = {}
local function push(n) nodes[#nodes+1] = n end
local it = list[7]
UI.Controller:push_room_thumb(push, "select.card.1", it,
  { x = 250, y = 330, w = 279, h = 388.8 }, "select")
local cells, walls, doors, hiddenRooms, furn, tinted = 0, 0, 0, 0, 0, 0
for _, n in ipairs(nodes) do
  if n.id:find("%.cell%.") then cells = cells + 1; if type(n.tint) == "table" then tinted = tinted + 1 end end
  if n.id:find("%.wall%.") then walls = walls + 1 end
  if n.id:find("%.door%.") then doors = doors + 1 end
  if n.id:find("%.room%.") and n.visible == false then hiddenRooms = hiddenRooms + 1 end
  if n.id:find("table") or n.id:find("plant") or n.id:find("statue")
     or n.id:find("shelf") or n.id:find("chair") or n.id:find("rug") then furn = furn + 1 end
end
print("THUMB:" .. table.concat({ tostring(cells), tostring(walls), tostring(doors),
  tostring(hiddenRooms), tostring(tinted), tostring(furn), tostring(#nodes) }, ","))
-- 底部关卡名样式
local ad = setmetatable({ cfg = {} }, EA.Adapter)
print("STYLE:" .. tostring(ad:color_of_style("card.name")))
-- 选关卡片文本口径（短名 / 规格）
local parts = UI.Controller.level_card_parts({ opts = {} }, it)
print("PARTS:" .. tostring(parts.short) .. "|" .. tostring(parts.title) .. "|" .. tostring(parts.info))
`;

function modules(src) {
  const i = src.indexOf('local FORCE_LEVEL = nil');
  if (i < 0 || src.indexOf('local FORCE_LEVEL = nil', i + 1) >= 0) throw Error('模块段锚点异常');
  return src.slice(0, i);
}
function run(file, tag) {
  const tmp = path.join(os.tmpdir(), `gil696_thumb_${tag}_${process.pid}.lua`);
  fs.writeFileSync(tmp, modules(fs.readFileSync(file, 'utf8')) + PROBE, 'utf8');
  let out = '';
  try {
    out = execFileSync(LUA, [tmp], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'],
                                    shell: true, timeout: 180000 });
  } catch (e) {
    throw Error(tag + ' Lua 运行失败：' + String(e.stderr || e.message).slice(0, 1200));
  } finally { fs.rmSync(tmp, { force: true }); }
  const lineOf = p => (out.split('\n').find(l => l.startsWith(p)) || '').replace(/\r/g, '').trim().slice(p.length);
  return { list: lineOf('LIST:'), thumb: lineOf('THUMB:'), style: lineOf('STYLE:'), parts: lineOf('PARTS:') };
}

const A = run(F695, '695');
const B = run(F696, '696');
const checks = [];
const ck = (name, ok, detail) => checks.push({ name, pass: !!ok, detail: String(detail ?? '') });

// ① 695 对照：ui_list 没有 room_grid/walls/doors ⇒ 缩略图无从画起
ck('695 对照：ui_list 无 room_grid', A.list.split(';').every(r => r.split(',')[1] === '0'), A.list.slice(0, 120));
// ② 696：7 关逐格房间网格齐全
const bl = B.list.split(';').filter(Boolean);
ck('696 ui_list 返回 7 关', bl.length === 7, String(bl.length));
for (const row of bl) {
  const [id, gd, want, nw, nd] = row.split(',');
  ck(`${id} room_grid 逐格数 == rows*cols`, Number(gd) === Number(want) && Number(gd) > 0, `${gd}/${want}`);
  ck(`${id} walls/doors 非空`, Number(nw) > 0 && Number(nd) > 0, `${nw}/${nd}`);
}
// ③ 缩略图节点：36 格 + 17 墙 + 5 门 + 6 个隐藏旧色块，零家具
const [cells, walls, doors, hidden, tinted, furn, total] = B.thumb.split(',').map(Number);
ck('第7关缩略图 36 个格子节点', cells === 36, cells);
ck('36 格全部带房间底色 tint', tinted === 36, tinted);
ck('17 段墙节点', walls === 17, walls);
ck('5 段门节点', doors === 5, doors);
ck('旧 6 个房间大色块全部隐藏', hidden === 6, hidden);
ck('缩略图零家具节点（用户要求省略）', furn === 0, furn);
ck('节点总数 = 36+17+5+6', total === 64, total);
// ④ 关卡名样式与短名
ck('card.name 样式返回深棕 0xFF4A2E1C', Number(B.style) === 0xFF4A2E1C, B.style);
const [short, title, info] = B.parts.split('|');
ck('关卡短名去掉「案件 007 · 」前缀', short === '旋转档案' && title.indexOf('案件 007') === 0, `${short} / ${title}`);
ck('规格信息仍保留 6x6 与嫌疑人数', info.indexOf('6x6') === 0 && info.indexOf('名嫌疑人') > 0, info);

const failed = checks.filter(c => !c.pass);
const out = { version: 696, pass: checks.length - failed.length, fail: failed.length,
              total: checks.length, list695: A.list, list696: B.list, thumb696: B.thumb,
              style696: B.style, parts696: B.parts, checks };
fs.writeFileSync(path.join(DIR, '696_缩略图验证.json'), JSON.stringify(out, null, 2));
console.log(`696 缩略图行为级验证 ${out.pass}/${out.total} PASS`);
console.log('  THUMB(格,墙,门,隐藏旧块,带色,家具,总节点):', B.thumb);
console.log('  STYLE:', B.style, ' PARTS:', B.parts);
for (const f of failed) console.log('  FAIL:', f.name, '|', f.detail);
process.exit(failed.length ? 1 : 0);
