// 从归档的 v12 派生。可传入尚不存在的输出路径，环境需要 Node 和 Lua。
import fs from 'node:fs';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {loadTree, findScriptLeaf, writeGil} from './gil/gilwrite.mjs';

const repo = fileURLToPath(new URL('../', import.meta.url));
const stem = '742_调查背包美术还原';
const base = path.join(repo, stem, stem + '_v12.gil');
const out = path.resolve(process.argv[2] || path.join(repo, stem, stem + '_v13.gil'));
assert(!fs.existsSync(out), '输出文件已存在');
const archive = loadTree(base);
assert.equal(createHash('sha256').update(archive.src).digest('hex'), '0be919ee32d24d35c9253d5d0b6adb203515858166de15f1dbbd596819765776');
const leaf = findScriptLeaf(archive);
let lua = leaf.buf.toString('utf8');
function patch(before, after) {
  assert(lua.includes(before) && lua.indexOf(before) === lua.lastIndexOf(before), '补丁位置不唯一：' + before.slice(0, 80));
  lua = lua.replace(before, () => after);
}

// 静态规则仅建一次。保留关内 home/select 无点号前缀及二级 room.label. 的语义。
const hideStart = lua.indexOf('local function apply_screen_hide(nodes, screen)');
const hideEnd = lua.indexOf('    if id == "home" then hide', hideStart);
assert(hideStart >= 0 && hideEnd > hideStart);
patch(lua.slice(hideStart, hideEnd), `local hide_exact = {
  topbar=true, toolbar=true, left=true, board=true, right=true, toast=true,
  modal=true, intro=true, clues=true, selbar=true, ["tpl-container"]=true,
  ["hit.back"]=true, ["hit.submit"]=true, ["hit.redo"]=true, ["hit.undo"]=true,
  ["hit.hint"]=true, ["hit.ok"]=true, ["hit.no"]=true,
}
local hide_group = {clue=true, hud=true, tray=true, action=true, hex=true, selbtn=true, tpl=true}
local function apply_screen_hide(nodes, screen)
  if nodes == nil then return end
  local other = screen == "home" and "select" or "home"
  for i = 1, #nodes do
    local id = nodes[i].id
    local hide
    if screen == nil then
      hide = id:sub(1,4) == "home" or id:sub(1,6) == "select"
    else
      local group = id:match("^([^.]+)%.")
      hide = hide_exact[id] or hide_group[group] or group == other
          or (group == "room" and id:sub(1,11) == "room.label.")
    end
`);
// 只在 create_control 之后复用成功的存在性检查。nil 和异常继续沿旧路径重试。
patch('    local bucket = self._props[n.id]', `    local found = false
    local function exists_now()
      if found or type(adapter.find) ~= "function" then return true end
      local ok, handle = pcall(adapter.find, adapter, n.id)
      found = ok and handle ~= nil
      return found or not ok
    end
    local bucket = self._props[n.id]`);
patch(`          local exists = true
          if type(adapter.find) == "function" then
            local e2, r2 = pcall(function() return adapter:find(n.id) end)
            if e2 then exists = (r2 ~= nil) end
          end`, '          local exists = exists_now()');
patch('          if ok and exists then\n            last[k]', '          if not ok then found = false end\n          if ok and exists then\n            last[k]');
patch(`      local rect_exists = true
      if type(adapter.find) == "function" then
        local e3, r3 = pcall(function() return adapter:find(n.id) end)
        if e3 then rect_exists = (r3 ~= nil) end
      end`, '      local rect_exists = exists_now()');
const marker = '构建标记 v742 / 调查背包美术还原 v12';
assert(lua.includes(marker));
lua = lua.replaceAll(marker, '构建标记 v742 / 调查背包美术还原 v13');

function measure(buf, label) {
  const test = spawnSync('lua', [path.join(repo, 'tests/shop_cold_render.lua')], {input:buf, encoding:'utf8', timeout:60000});
  assert.equal(test.status, 0, test.stderr || test.error?.message);
  const line = test.stdout.match(/COLD=(\d+) WRITES=(\d+) COLD_FINDS=(\d+) FINDS=(\d+)/);
  assert(line, test.stdout);
  console.log(label, line[0]);
  return line.slice(1).map(Number);
}
const baseline = measure(leaf.buf, 'v12');
leaf.field.payload = Buffer.from(lua);
writeGil(archive, out, {label:'742 v13', expectDiffs:1, expectMarker:'v742', assert(saved) {
  const buf = findScriptLeaf(saved).buf;
  assert(buf.equals(leaf.field.payload));
  const result = measure(buf, 'v13');
  assert.deepEqual(result.slice(0,2), baseline.slice(0,2), '属性写入数发生变化');
  for (const i of [2,3]) assert(result[i] < baseline[i] * 0.6, '控件查找降幅未达 40%');
  return true;
}});
