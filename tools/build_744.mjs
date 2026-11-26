// 744：从 743_全面性能优化.gil 派生，仅修改内嵌 Lua，不覆盖基准或旧存档。
// 优化目标：消除稳态每帧/周期性的引擎跨界调用、全树重扫与热路径闭包 GC，保留全部 pcall 与迟到自愈语义。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { loadTree, findScriptLeaf, writeGil } from './gil/gilwrite.mjs';
import { encodeMsg } from './gil/gilread.mjs';

const repo = fileURLToPath(new URL('../', import.meta.url));
const temp = process.env.FEIBO_TMP || 'C:/Users/18182/AppData/Local/Temp/feibo/52d0fd52-fa9b-42d4-bdef-141bcf577d91';
const out = path.resolve(process.argv[2] && !process.argv[2].startsWith('--')
  ? process.argv[2]
  : path.join(repo, '744_深度运行时优化/744_深度运行时优化.gil'));
const base = path.join(repo, '743_全面性能优化/743_全面性能优化.gil');
const isCandidate = process.argv.includes('--candidate');
if (!isCandidate) assert(!fs.existsSync(out), '输出已存在，拒绝覆盖：' + out);

const sha = (b) => createHash('sha256').update(b).digest('hex');
const g = loadTree(base);
const leaf = findScriptLeaf(g);
const original = leaf.buf.toString('utf8');
assert.equal(sha(g.src), '66654aabd7d9dcaeac8fb6a5e4c21db29c65c4887be931ba0f56b12ababe66cd', '基准 743 SHA256 不匹配');

let lua = original;
const patches = [];
function patch(tag, before, after) {
  const parts = lua.split(before);
  assert.equal(parts.length, 2, `补丁不唯一或未命中 [${tag}] (matches=${parts.length - 1})`);
  lua = lua.replace(before, () => after);
  patches.push(tag);
}

// ── 1. apply_screen_hide：用普通字符查找替代逐节点正则匹配 ─────────────────
patch(
  'apply_screen_hide去正则',
  `      local group = id:match("^([^.]+)%.")`,
  `      local dot = id:find(".", 1, true)
      local group = (dot and dot > 1) and id:sub(1, dot - 1) or nil`
);

// ── 2. Controller:_set_prop：消除每次属性写入的匿名闭包分配 ─────────────────
patch(
  '_set_prop去闭包',
  `function Controller:_set_prop(adapter, id, key, value, nkey)
  local ok, res = pcall(function() return adapter:set_property(id, key, value, nkey) end)`,
  `function Controller:_set_prop(adapter, id, key, value, nkey)
  local ok, res = pcall(adapter.set_property, adapter, id, key, value, nkey)`
);

// ── 3. Controller:_render_impl：首字节过滤 select_content + 循环去闭包 + 重试标记 ──
patch(
  '_render_impl辅助函数与select_content快判',
  `local function rect_record743(last, rect)
  local saved = last.__rect
  if saved == nil then saved = {}; last.__rect = saved end
  saved.x, saved.y, saved.w, saved.h = rect.x, rect.y, rect.w, rect.h
end
function Controller:_render_impl(adapter, force)`,
  `local function rect_record743(last, rect)
  local saved = last.__rect
  if saved == nil then saved = {}; last.__rect = saved end
  saved.x, saved.y, saved.w, saved.h = rect.x, rect.y, rect.w, rect.h
end
local function is_select_content744(id)
  local b = id:byte(1)
  if b == 101 then return id:sub(1, 5) == "econ." end
  if b == 115 then
    return id == "select.thumb.pool" or (id:sub(1, 12) == "select.card." and id:match("^select%.card%.%d+%.") ~= nil)
  end
  if b == 104 then
    return id:sub(1, 16) == "hit.select.card." and id:match("^hit%.select%.card%.%d+$") ~= nil
  end
  return false
end
function Controller:_render_impl(adapter, force)
  self._pending_retry744 = false`
);

patch(
  '_render_impl循环去闭包',
  `    -- 701：选关静态控件会迟到或重建；未找到不能当作已经下发。
    local select_content = n.id:match("^econ%.") ~= nil or n.id == "select.thumb.pool"
      or n.id:match("^select%.card%.%d+%.") ~= nil
      or n.id:match("^hit%.select%.card%.%d+$") ~= nil
    local was_created743 = self._created[n.id]
    local select_ctrl = nil
    if select_content and type(adapter.find) == "function" then
      pcall(function() select_ctrl = adapter:find(n.id) end)
      self._select_handles = self._select_handles or {}
      if self._select_handles[n.id] ~= select_ctrl then
        drop_props_of(n.id)
        self._created[n.id] = nil
        self._select_handles[n.id] = select_ctrl
      end
    end
    if not self._created[n.id] then
      local ok_c, err_c = pcall(function() adapter:create_control(n) end)`,
  `    -- 701：选关静态控件会迟到或重建；未找到不能当作已经下发。
    local select_content = is_select_content744(n.id)
    local was_created743 = self._created[n.id]
    local select_ctrl = nil
    if select_content and type(adapter.find) == "function" then
      local ok_f, res_f = pcall(adapter.find, adapter, n.id)
      if ok_f then select_ctrl = res_f end
      self._select_handles = self._select_handles or {}
      if self._select_handles[n.id] ~= select_ctrl then
        drop_props_of(n.id)
        self._created[n.id] = nil
        self._select_handles[n.id] = select_ctrl
      end
    end
    if not self._created[n.id] then
      local ok_c, err_c = pcall(adapter.create_control, adapter, n)`
);

patch(
  '_render_impl记录待重试状态',
  `          elseif not exists then
            if not select_content then last[k] = v end
          else
            local why = (not exists) and "控件一直没找到（find 返回 nil）"
              or "控件在、但适配层说这次没写进去（子控件没就绪？）"
            if not select_content and retry_more(n.id, k, why, exists) == false then
              last[k] = v           
            end
          end`,
  `          elseif not exists then
            if not select_content then last[k] = v else self._pending_retry744 = true end
          else
            local why = (not exists) and "控件一直没找到（find 返回 nil）"
              or "控件在、但适配层说这次没写进去（子控件没就绪？）"
            if not select_content and retry_more(n.id, k, why, exists) == false then
              last[k] = v
            else
              self._pending_retry744 = true
            end
          end`
);

patch(
  '_render_impl矩形待重试与销毁特效去闭包',
  `      elseif not rect_exists then
        if not select_content then
          rect_record743(last, n.rect)
        end
      elseif not select_content and retry_more(n.id, "__rect", "位置没写进去（控件在，但句柄失效 / 位置被拒）", true) == false then
        rect_record743(last, n.rect)
      end
    end
  end
  for id in pairs(self._created) do
    if not seen[id] then
      if stale_legacy(id) then
        self._created[id] = nil
        drop_props_of(id)
      else
        pcall(function() adapter:destroy_control(id) end)
        self._created[id] = nil
        drop_props_of(id)
      end
    end
  end
  for i = 1, #self.effects do
    local e = self.effects[i]
    if not stale_legacy(e.target) then
      pcall(function() adapter:play_effect(e.target, e.kind, e) end)
    end
  end`,
  `      elseif not rect_exists then
        if not select_content then
          rect_record743(last, n.rect)
        else
          self._pending_retry744 = true
        end
      elseif not select_content and retry_more(n.id, "__rect", "位置没写进去（控件在，但句柄失效 / 位置被拒）", true) == false then
        rect_record743(last, n.rect)
      else
        self._pending_retry744 = true
      end
    end
  end
  for id in pairs(self._created) do
    if not seen[id] then
      if stale_legacy(id) then
        self._created[id] = nil
        drop_props_of(id)
      else
        pcall(adapter.destroy_control, adapter, id)
        self._created[id] = nil
        drop_props_of(id)
      end
    end
  end
  for i = 1, #self.effects do
    local e = self.effects[i]
    if not stale_legacy(e.target) then
      pcall(adapter.play_effect, adapter, e.target, e.kind, e)
    end
  end`
);

// ── 4. Adapter 静态 pcall 助手 + index_in 去闭包 + lookup 退避清理 ──────────
patch(
  'Adapter去闭包助手与index_in',
  `function Adapter:invalidate_lookups(why)
  self._misses = nil
  self._floor_slots = nil
  self._floor_faces = nil
  self._floor_layout = nil
  self.controls = {}
  self._subtree_dirty = true
  self._baked_dirty = true
  self._lookup_gen = (self._lookup_gen or 0) + 1
  if self.cfg and self.cfg.debug_lookup and print then
    print(PREFIX .. "控件名缓存作废（第 " .. tostring(self._lookup_gen) .. " 代）："
      .. tostring(why))
  end
end
function Adapter:drop_lookup(name)
  if name == nil then return end
  self.controls[name] = nil
  if self._misses ~= nil then self._misses[name] = nil end
end
local function index_in(ctrl, depth, idx, n)
  if ctrl == nil or depth > 16 then return n end
  n = n + 1
  local ok, cname = pcall(function() return ctrl.name end)
  if ok and cname ~= nil and idx[cname] == nil then idx[cname] = ctrl end
  local okc, children = pcall(function() return ctrl:GetChildren() end)
  if okc and type(children) == "table" then
    for i = 1, #children do n = index_in(children[i], depth + 1, idx, n) end
  end
  return n
end`,
  `local function p744_name(c) return c.name end
local function p744_kids(c) return c:GetChildren() end
local function p744_child(c, k) return c:GetChild(k) end
local function p744_vis(c) return c.visible end
local function p744_set_vis(c, v) c:SetVisible(v) end
local function p744_ray_get(c) return c.raycastTarget end
local function p744_ray_set(c, v) c.raycastTarget = v end
local function p744_cur_set(c) if c.showCursor ~= true then c.showCursor = true end end
local function p744_field(c, k) return c[k] end
function Adapter:invalidate_lookups(why)
  self._misses = nil
  self._miss_streak = nil
  self._name_idx_stable = 0
  self._floor_slots = nil
  self._floor_faces = nil
  self._floor_layout = nil
  self.controls = {}
  self._subtree_dirty = true
  self._subtree_dirty_ids = nil
  self._baked_dirty = true
  self._lookup_gen = (self._lookup_gen or 0) + 1
  if self.cfg and self.cfg.debug_lookup and print then
    print(PREFIX .. "控件名缓存作废（第 " .. tostring(self._lookup_gen) .. " 代）："
      .. tostring(why))
  end
end
function Adapter:drop_lookup(name)
  if name == nil then return end
  self.controls[name] = nil
  if self._misses ~= nil then self._misses[name] = nil end
  if self._miss_streak ~= nil then self._miss_streak[name] = nil end
end
local function index_in(ctrl, depth, idx, n)
  if ctrl == nil or depth > 16 then return n end
  n = n + 1
  local ok, cname = pcall(p744_name, ctrl)
  if ok and cname ~= nil and idx[cname] == nil then idx[cname] = ctrl end
  local okc, children = pcall(p744_kids, ctrl)
  if okc and type(children) == "table" then
    for i = 1, #children do n = index_in(children[i], depth + 1, idx, n) end
  end
  return n
end`
);

// ── 5. path_lookup_655 去闭包 + 动态分支首字节快筛 ──────────────────────────
patch(
  'path_lookup_655去闭包与首字节过滤',
  `  if route == nil then
    if name:match("^econ%.") then
      route = (name:match("^econ%.shop736%.") or name:match("^econ%.bag741%.")) and "root/econ.ui742/" .. name or "root/" .. name
    elseif name == "art641.select" then
      route = "root/art641.select"
    elseif name == "art642.select.frames" then
      route = "root/art641.select/art642.select.frames"
    elseif name == "grp653.static.1.art642.select.frames" then
      route = "root/art641.select/art642.select.frames/grp653.static.1.art642.select.frames"
    elseif name:match("^art647%.select%.card%.%d+%.paper$") then
      route = "root/art641.select/art642.select.frames/grp653.static.1.art642.select.frames/" .. name
    elseif name == "select.thumb.pool" then
      route = "root/select.thumb.pool"
    elseif name:match("^select%.card%.%d+%.boardbg$")
        or name:match("^select%.card%.%d+%.cell%.")
        or name:match("^select%.card%.%d+%.wall%.")
        or name:match("^select%.card%.%d+%.door%.") then
      route = "root/select.thumb.pool/" .. name
    else
      return nil
    end
    STATIC_PATH_655[name] = route
  end
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
  end`,
  `  if route == nil then
    local b = type(name) == "string" and name:byte(1) or 0
    if b == 101 and name:sub(1, 5) == "econ." then
      route = (name:sub(1, 13) == "econ.shop736." or name:sub(1, 12) == "econ.bag741.") and "root/econ.ui742/" .. name or "root/" .. name
    elseif b == 97 then
      if name == "art641.select" then
        route = "root/art641.select"
      elseif name == "art642.select.frames" then
        route = "root/art641.select/art642.select.frames"
      elseif name:sub(1, 19) == "art647.select.card." and name:match("^art647%.select%.card%.%d+%.paper$") then
        route = "root/art641.select/art642.select.frames/grp653.static.1.art642.select.frames/" .. name
      else
        return nil
      end
    elseif b == 103 and name == "grp653.static.1.art642.select.frames" then
      route = "root/art641.select/art642.select.frames/grp653.static.1.art642.select.frames"
    elseif b == 115 then
      if name == "select.thumb.pool" then
        route = "root/select.thumb.pool"
      elseif name:sub(1, 12) == "select.card." and (name:match("^select%.card%.%d+%.boardbg$")
          or name:match("^select%.card%.%d+%.cell%.")
          or name:match("^select%.card%.%d+%.wall%.")
          or name:match("^select%.card%.%d+%.door%.")) then
        route = "root/select.thumb.pool/" .. name
      else
        return nil
      end
    else
      return nil
    end
    STATIC_PATH_655[name] = route
  end
  -- 首次使用时把紧凑字符串路径拆成数组并回写，后续查找不再解析。
  if type(route) == "string" then
    local parts = {}
    for seg in route:gmatch("[^/]+") do parts[#parts + 1] = seg end
    STATIC_PATH_655[name] = parts
    route = parts
  end
  for i = 1, #roots do
    local cur = roots[i]
    local ok, rn = pcall(p744_name, cur)
    if ok and rn == route[1] then
      for k = 2, #route do
        local good, child = pcall(p744_child, cur, route[k])
        if not good or child == nil then cur = nil; break end
        cur = child
      end
      if cur ~= nil then
        local good, actual = pcall(p744_name, cur)
        if good and actual == name then return cur end
      end
    end
  end`
);

// ── 6. _build_name_index / _index_lookup / find：稳态指数退避（根治每秒全树 8578 DFS）──
patch(
  '全树索引与缺失查找稳态指数退避',
  `function Adapter:_build_name_index(roots)
  local idx = {}
  local n = 0
  for i = 1, #roots do n = index_in(roots[i], 0, idx, n) end
  self._name_idx = idx
  self._name_idx_at = self.clock
  self._name_idx_gen = self._lookup_gen
  self._name_idx_builds = (self._name_idx_builds or 0) + 1
  self._name_idx_nodes = n
  return idx
end
function Adapter:_index_lookup(name, roots)
  local idx = self._name_idx
  local walked = false
  -- 655: 结构代数变化立即重建；同一代数内最多每 1.0 秒复核一次，
  -- 既消除逐帧全树 DFS，又保留客户端迟到控件/自行重建的自愈能力。
  local stale = idx == nil or self._name_idx_gen ~= self._lookup_gen
    or self._name_idx_at == nil or (self.clock - self._name_idx_at) >= 1.0
  if stale then
    idx = self:_build_name_index(roots); walked = true
  end
  local hit = idx[name]
  if hit ~= nil then
    local ok, got = pcall(function() return hit.name end)
    if ok and got == name then return hit end
  end
  -- 698：有效索引中的缺项也是有效结果；不为每个缺失名字重新扫描。
  -- TTL/结构代数负责刷新，失效句柄则单独重建一次。
  if hit ~= nil and not walked then
    idx = self:_build_name_index(roots)
    return idx[name]
  end
  return nil
end`,
  `function Adapter:_build_name_index(roots)
  local prev_gen = self._name_idx_gen
  local prev_n = self._name_idx_nodes
  local idx = {}
  local n = 0
  for i = 1, #roots do n = index_in(roots[i], 0, idx, n) end
  self._name_idx = idx
  self._name_idx_at = self.clock
  self._name_idx_gen = self._lookup_gen
  self._name_idx_builds = (self._name_idx_builds or 0) + 1
  self._name_idx_nodes = n
  -- 744：同一结构代数下若两次全树扫描节点数一致且非空，树已稳态，按 1→2→4→8→16s 退避复核；
  -- 代数变更或句柄失效立即归零恢复 1s 敏感度，兼顾稳态零抖动与迟到自愈。
  if prev_gen == self._lookup_gen and prev_n == n and n > 0 then
    self._name_idx_stable = math.min(4, (self._name_idx_stable or 0) + 1)
  else
    self._name_idx_stable = 0
  end
  return idx
end
function Adapter:_index_lookup(name, roots)
  local idx = self._name_idx
  local walked = false
  local idx_ttl = (self._name_idx_gen == self._lookup_gen)
    and math.min(16.0, 2 ^ (self._name_idx_stable or 0))
    or 1.0
  local stale = idx == nil or self._name_idx_gen ~= self._lookup_gen
    or self._name_idx_at == nil or (self.clock - self._name_idx_at) >= idx_ttl
  if stale then
    idx = self:_build_name_index(roots); walked = true
  end
  local hit = idx[name]
  if hit ~= nil then
    local ok, got = pcall(p744_name, hit)
    if ok and got == name then return hit end
  end
  -- 698：有效索引中的缺项也是有效结果；不为每个缺失名字重新扫描。
  -- TTL/结构代数负责刷新，失效句柄则单独重建一次并复位稳态退避。
  if hit ~= nil and not walked then
    self._name_idx_stable = 0
    idx = self:_build_name_index(roots)
    return idx[name]
  end
  return nil
end`
);

patch(
  'Adapter:find缺失项同代数指数退避',
  `  if self._lookup_hits > 0 then
    if self._misses == nil then self._misses = {} end
    local ttl = (self.cfg and self.cfg.lookup_miss_ttl) or 1.0
    local old = self._misses[name]
    if old == nil then
      self._misses[name] = self.clock + ttl      
    elseif old == false or self.clock >= old then
      self._misses[name] = self.clock + ttl                 
    end
  end
  return nil
end
function Adapter:_note_lookup_hit(name)
  self._lookup_hits = self._lookup_hits + 1
  if self._hidden_ids ~= nil and self._hidden_ids[name] then
    self._subtree_dirty = true
  end
end`,
  `  if self._lookup_hits > 0 then
    if self._misses == nil then self._misses = {} end
    local base_ttl = (self.cfg and self.cfg.lookup_miss_ttl) or 1.0
    local old = self._misses[name]
    if old == nil or old == false or self.clock >= old then
      local streaks = self._miss_streak
      if streaks == nil then streaks = {}; self._miss_streak = streaks end
      local st = math.min(6, (streaks[name] or 0) + 1)
      streaks[name] = st
      local shift = (st > 2) and (st - 2) or 0
      local eff_ttl = math.min(math.max(base_ttl, 16.0), base_ttl * (2 ^ shift))
      self._misses[name] = self.clock + eff_ttl
    end
  end
  return nil
end
function Adapter:_note_lookup_hit(name)
  self._lookup_hits = self._lookup_hits + 1
  if self._miss_streak ~= nil then self._miss_streak[name] = nil end
  if self._hidden_ids ~= nil and self._hidden_ids[name] then
    self._subtree_dirty_ids = self._subtree_dirty_ids or {}
    self._subtree_dirty_ids[name] = true
  end
end`
);

// ── 7. Adapter:enable_cursor：历史废弃容器名缺失时允许按稳定集合收敛 + 去闭包 ──
patch(
  'enable_cursor稳态收敛与去闭包',
  `  for i = 1, #CURSOR_CONTAINERS do
    local ctrl = self:find(CURSOR_CONTAINERS[i])
    if ctrl ~= nil then
      local ok = pcall(function() if ctrl.showCursor ~= true then ctrl.showCursor = true end end)
      if ok then n = n + 1 end
    end
  end
  local parts = {}
  local found, all_true = 0, true           
  for i = 1, #CURSOR_CONTAINERS do
    local ctrl = self:find(CURSOR_CONTAINERS[i])
    if ctrl ~= nil then
      found = found + 1
      local sc, kd = "?", "?"
      pcall(function() sc = tostring(ctrl.showCursor) end)
      if sc ~= "true" then all_true = false end
      pcall(function() kd = tostring(ctrl.kind) end)
      if kd == "nil" then pcall(function() kd = tostring(ctrl.Kind) end) end
      if kd == "nil" then pcall(function() kd = tostring(ctrl.type) end) end
      if kd == "nil" then pcall(function() kd = tostring(ctrl.controlType) end) end
      parts[#parts + 1] = CURSOR_CONTAINERS[i] .. "(kind=" .. kd .. ",cur=" .. sc .. ")"
    else
      all_true = false
      parts[#parts + 1] = CURSOR_CONTAINERS[i] .. "=**找不到**"
    end
  end
  local line = table.concat(parts, "  ")
  if #parts > 0 and print and line ~= self._cursor_line then
    self._cursor_line = line
    print("[murdoku] 常驻光标回读（门控②）：" .. line)
  end
  st.n = n
  if found >= #CURSOR_CONTAINERS and all_true then
    st.idle = st.idle + 1
    if st.idle >= 3 then
      st.done = true
      if print and not self._cursor_done_logged then
        self._cursor_done_logged = true
        print(PREFIX .. "常驻光标：已收敛（" .. tostring(found) .. " 个容器 showCursor 全为 true）"
          .. " ⇒ 不再每 20 帧重扫；换屏/换关会重新武装")
      end
    end
  else
    st.idle = 0                             
  end`,
  `  for i = 1, #CURSOR_CONTAINERS do
    local ctrl = self:find(CURSOR_CONTAINERS[i])
    if ctrl ~= nil then
      local ok = pcall(p744_cur_set, ctrl)
      if ok then n = n + 1 end
    end
  end
  local parts = {}
  local found, present_all_true = 0, true
  for i = 1, #CURSOR_CONTAINERS do
    local ctrl = self:find(CURSOR_CONTAINERS[i])
    if ctrl ~= nil then
      found = found + 1
      local ok_sc, v_sc = pcall(p744_field, ctrl, "showCursor")
      local sc = ok_sc and tostring(v_sc) or "?"
      if sc ~= "true" then present_all_true = false end
      local ok_k, v_k = pcall(p744_field, ctrl, "kind")
      local kd = ok_k and tostring(v_k) or "?"
      if kd == "nil" then ok_k, v_k = pcall(p744_field, ctrl, "Kind"); if ok_k then kd = tostring(v_k) end end
      if kd == "nil" then ok_k, v_k = pcall(p744_field, ctrl, "type"); if ok_k then kd = tostring(v_k) end end
      if kd == "nil" then ok_k, v_k = pcall(p744_field, ctrl, "controlType"); if ok_k then kd = tostring(v_k) end end
      parts[#parts + 1] = CURSOR_CONTAINERS[i] .. "(kind=" .. kd .. ",cur=" .. sc .. ")"
    else
      parts[#parts + 1] = CURSOR_CONTAINERS[i] .. "=**找不到**"
    end
  end
  local line = table.concat(parts, "  ")
  if #parts > 0 and print and line ~= self._cursor_line then
    self._cursor_line = line
    print("[murdoku] 常驻光标回读（门控②）：" .. line)
  end
  st.n = n
  local need_idle = (found >= #CURSOR_CONTAINERS) and 3 or 6
  if found > 0 and present_all_true and st.last_found == found then
    st.idle = st.idle + 1
    if st.idle >= need_idle then
      st.done = true
      if print and not self._cursor_done_logged then
        self._cursor_done_logged = true
        print(PREFIX .. "常驻光标：已收敛（" .. tostring(found) .. " 个容器 showCursor 全为 true）"
          .. " ⇒ 不再每 20 帧重扫；换屏/换关会重新武装")
      end
    end
  else
    st.last_found = found
    st.idle = 0
  end`
);

// ── 8. Adapter:enable_raycast：walk 内 8578 节点零闭包 ──────────────────────
patch(
  'enable_raycast去闭包',
  `    local before = nil
    pcall(function() before = c.raycastTarget end)
    if before ~= nil then
      seen = seen + 1
      if before ~= want then
        local ok = pcall(function() c.raycastTarget = want end)
        if ok then
          set = set + 1
          if #samples < 6 then
            local nm = "?"
            pcall(function() nm = tostring(c.name) end)
            samples[#samples + 1] = nm .. ":" .. tostring(before) .. "->true"
          end
        end
      end
    end
    local kids = nil
    pcall(function() kids = c:GetChildren() end)`,
  `    local ok_b, before = pcall(p744_ray_get, c)
    if not ok_b then before = nil end
    if before ~= nil then
      seen = seen + 1
      if before ~= want then
        local ok = pcall(p744_ray_set, c, want)
        if ok then
          set = set + 1
          if #samples < 6 then
            local ok_n, nm = pcall(p744_name, c)
            samples[#samples + 1] = (ok_n and tostring(nm) or "?") .. ":" .. tostring(before) .. "->true"
          end
        end
      end
    end
    local ok_k, kids = pcall(p744_kids, c)
    if not ok_k then kids = nil end`
);

// ── 9. Adapter:set_property("visible") + enforce_hidden_subtrees 增量隐藏子树 ──
patch(
  'visible分支增量标记隐藏子树',
  `    local vis = value and true or false
    if ctrl.SetVisible then pcall(function() ctrl:SetVisible(vis) end) end
    self._hidden_ids = self._hidden_ids or {}
    if vis then self._hidden_ids[id] = nil else self._hidden_ids[id] = true end
    if vis and id:sub(1, 5) == "cell." then
      self._overlay_dirty = true
    end
    self._subtree_dirty = true`,
  `    local vis = value and true or false
    if ctrl.SetVisible then pcall(p744_set_vis, ctrl, vis) end
    self._hidden_ids = self._hidden_ids or {}
    if vis then
      self._hidden_ids[id] = nil
      if self._subtree_dirty_ids ~= nil then self._subtree_dirty_ids[id] = nil end
    else
      self._hidden_ids[id] = true
      self._subtree_dirty_ids = self._subtree_dirty_ids or {}
      self._subtree_dirty_ids[id] = true
    end
    if vis and id:sub(1, 5) == "cell." then
      self._overlay_dirty = true
    end`
);

patch(
  'enforce_hidden_subtrees增量与读回守卫',
  `function Adapter:enforce_hidden_subtrees()
  self._subtree_dirty = false
  local hid = self._hidden_ids
  if hid == nil then return end
  local function decor(nm)
    if nm == nil or nm == "" then return false end
    return DECOR[nm] == true
  end
  local function nameOf(c)
    local nm = nil
    pcall(function() nm = c.name end)
    return nm
  end
  for id in pairs(hid) do
    if true then    
      local c = self:find(id)
      if c ~= nil then
        local kids = nil
        pcall(function() kids = c:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil and k.SetVisible then
              if not decor(nameOf(k)) then
                pcall(function() k:SetVisible(false) end)
                local kk = nil
                pcall(function() kk = k:GetChildren() end)
                if type(kk) == "table" then
                  for j = 1, math.min(#kk, 32) do
                    if kk[j] ~= nil and kk[j].SetVisible and not decor(nameOf(kk[j])) then
                      pcall(function() kk[j]:SetVisible(false) end)
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end`,
  `function Adapter:enforce_hidden_subtrees()
  local full = self._subtree_dirty
  self._subtree_dirty = false
  local pending = self._subtree_dirty_ids
  self._subtree_dirty_ids = nil
  local hid = self._hidden_ids
  if hid == nil then return end
  local targets = full and hid or pending
  if targets == nil then return end
  for id in pairs(targets) do
    if hid[id] then
      local c = self:find(id)
      if c ~= nil then
        local ok_k, kids = pcall(p744_kids, c)
        if ok_k and type(kids) == "table" then
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil and k.SetVisible then
              local ok_n, kn = pcall(p744_name, k)
              if not (ok_n and kn ~= nil and kn ~= "" and DECOR[kn] == true) then
                local ok_v, kv = pcall(p744_vis, k)
                if not ok_v or kv ~= false then pcall(p744_set_vis, k, false) end
                local ok_kk, kk = pcall(p744_kids, k)
                if ok_kk and type(kk) == "table" then
                  for j = 1, math.min(#kk, 32) do
                    local k2 = kk[j]
                    if k2 ~= nil and k2.SetVisible then
                      local ok_n2, kn2 = pcall(p744_name, k2)
                      if not (ok_n2 and kn2 ~= nil and kn2 ~= "" and DECOR[kn2] == true) then
                        local ok_v2, kv2 = pcall(p744_vis, k2)
                        if not ok_v2 or kv2 ~= false then pcall(p744_set_vis, k2, false) end
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end`
);

patch(
  'on_tick触发增量隐藏子树',
  `  if self._subtree_dirty then
    pcall(function() self:enforce_hidden_subtrees() end)
  end`,
  `  if self._subtree_dirty or (self._subtree_dirty_ids ~= nil and next(self._subtree_dirty_ids) ~= nil) then
    pcall(self.enforce_hidden_subtrees, self)
  end`
);

// ── 10. murdoku_set_vis 去闭包 + 非关内稳态免每秒全量 render ────────────────
patch(
  'murdoku_set_vis去闭包',
  `local function murdoku_set_vis(ad, nm, want, forcing, memo)
  if ad == nil then return 0 end
  local c = nil
  if ad.controls ~= nil then c = ad.controls[nm] end
  if c == nil then pcall(function() c = ad:find(nm) end) end
  if c == nil then return 0 end
  local cur_vis = nil
  pcall(function() cur_vis = c.visible end)
  if not forcing and cur_vis == want then
    memo[nm] = want
    return 0
  end
  if (not forcing) and memo[nm] == want and cur_vis == nil then return 0 end
  local okw = pcall(function() c:SetVisible(want) end)
  if okw then
    memo[nm] = want
    return 1
  end
  return 0
end`,
  `local function m744_vis_get(c) return c.visible end
local function m744_vis_set(c, v) c:SetVisible(v) end
local function murdoku_set_vis(ad, nm, want, forcing, memo)
  if ad == nil then return 0 end
  local c = nil
  if ad.controls ~= nil then c = ad.controls[nm] end
  if c == nil then
    local ok_f, res_f = pcall(ad.find, ad, nm)
    if ok_f then c = res_f end
  end
  if c == nil then return 0 end
  local ok_v, cur_vis = pcall(m744_vis_get, c)
  if not ok_v then cur_vis = nil end
  if not forcing and cur_vis == want then
    memo[nm] = want
    return 0
  end
  if (not forcing) and memo[nm] == want and cur_vis == nil then return 0 end
  local okw = pcall(m744_vis_set, c, want)
  if okw then
    memo[nm] = want
    return 1
  end
  return 0
end`
);

patch(
  '非关内稳态免每秒无故全量render',
  `  local sec = math.floor(current.core.elapsed or 0)
  if sec ~= current.last_tick or current.controller.dirty then
    current.last_tick = sec
    Murdoku.render()
  end`,
  `  local sec = math.floor(current.core.elapsed or 0)
  local need_sec_render = (sec ~= current.last_tick)
    and (current.controller.screen == nil or current.controller._pending_retry744 == true)
  if need_sec_render or current.controller.dirty then
    current.last_tick = sec
    Murdoku.render()
  end`
);

// ── 11. 入口层 help_visible / tut_visible / write_art_color650 去闭包 ────────
patch(
  'tut_visible与help_visible去闭包',
  `local function tut_visible(name)
  if adapter == nil or name == nil then return false end
  local c = nil
  pcall(function() c = adapter:find(name) end)
  if c == nil then return false end
  local v = nil
  pcall(function() v = c.visible end)
  return v == true
end`,
  `local function e744_vis(c) return c.visible end
local function e744_act(c) return c.active end
local function e744_set_vis(c, v) if c.SetVisible then c:SetVisible(v) else c.visible = v end end
local function e744_set_act(c, v) if c.SetActive then c:SetActive(v) end end
local function e744_last_sib(c) c:SetAsLastSibling() end
local function e744_get_kids(c) return c:GetChildren() end
local function e744_get_k(c, k) return c[k] end
local function e744_set_k(c, k, v) c[k] = v end
local function tut_visible(name)
  if adapter == nil or name == nil then return false end
  local ok_f, c = pcall(adapter.find, adapter, name)
  if not ok_f or c == nil then return false end
  local ok_v, v = pcall(e744_vis, c)
  return ok_v and v == true
end`
);

patch(
  'help_visible静态pcall去闭包',
  `local function help_visible(c, v)
  if c == nil then return end
  local actual = nil
  pcall(function() actual = c.visible end)
  if actual ~= v then
    pcall(function() if c.SetVisible then c:SetVisible(v) else c.visible = v end end)
  end
  if v then
    local active = nil
    pcall(function() active = c.active end)
    if active ~= true then pcall(function() if c.SetActive then c:SetActive(true) end end) end
  end
end`,
  `local function help_visible(c, v)
  if c == nil then return end
  local ok_v, actual = pcall(e744_vis, c)
  if not ok_v or actual ~= v then
    pcall(e744_set_vis, c, v)
  end
  if v then
    local ok_a, active = pcall(e744_act, c)
    if not ok_a or active ~= true then pcall(e744_set_act, c, true) end
  end
end`
);

patch(
  'write_art_color650去闭包',
  `  local actual = nil
  pcall(function() actual = c[key] end)
  if actual ~= want then pcall(function() c[key] = want end) end`,
  `  local ok_g, actual = pcall(e744_get_k, c, key)
  if not ok_g or actual ~= want then pcall(e744_set_k, c, key, want) end`
);

// ── 12. sync_adapt715r：撕边 591 叶缓存 + set_visible/transform 读回守卫 + 字号脏检查 ──
patch(
  'sync_adapt715r读回守卫与591撕边叶缓存',
  `  if gen~=st.gen then st.handles={};st.gen=gen;st.leaves=nil;st.page=nil end
  local function find(name)
    if not st.handles[name] then st.handles[name]=adapter:find(name) end
    return st.handles[name]
  end
  local cur=Murdoku and Murdoku.current()
  local page=(cur and cur.controller and cur.controller.screen) or 'home'
  local selecting=page=='select'
  local function set_visible(c,want)
    if not c then return false end
    local ok,matched=pcall(function()
      local wrote=false
      if c.SetActive then c:SetActive(want);wrote=true end
      if c.SetVisible then c:SetVisible(want);wrote=true end
      local a,v=c.active,c.visible
      return wrote and (a==want or v==want) and a~=not want and v~=not want
    end)
    return ok and matched
  end`,
  `  if gen~=st.gen then st.handles={};st.gen=gen;st.leaves=nil;st.leafState=nil;st.tearKids={};st.tearState={};st.cardFont={};st.page=nil end
  local function find(name)
    if not st.handles[name] then st.handles[name]=adapter:find(name) end
    return st.handles[name]
  end
  local cur=Murdoku and Murdoku.current()
  local page=(cur and cur.controller and cur.controller.screen) or 'home'
  local selecting=page=='select'
  local function set_visible(c,want)
    if not c then return false end
    local ok_a, a = pcall(e744_act, c)
    local ok_v, v = pcall(e744_vis, c)
    if ok_a and ok_v and (a==want or v==want) and a~=not want and v~=not want then return true end
    local ok,matched=pcall(function()
      local wrote=false
      if c.SetActive and (not ok_a or a~=want) then c:SetActive(want);wrote=true end
      if c.SetVisible and (not ok_v or v~=want) then c:SetVisible(want);wrote=true end
      local a2,v2=c.active,c.visible
      return wrote and (a2==want or v2==want) and a2~=not want and v2~=not want
    end)
    return ok and matched
  end`
);

patch(
  'sync_adapt715r_transform读回守卫',
  `  local function transform(name,x,y,s)
    local c=find(name)
    if not c then return false end
    local ok=pcall(function() c:SetAnchoredPosition(x,y);c:SetLocalScale(s,s,1) end)
    local a,b=adapt715r_pair(c,'GetLocalScale')
    local px,py=adapt715r_pair(c,'GetAnchoredPosition')
    return ok and a and b and px and py and math.abs(a-s)<eps and math.abs(b-s)<eps and math.abs(px-x)<eps and math.abs(py-y)<eps
  end`,
  `  local function transform(name,x,y,s)
    local c=find(name)
    if not c then return false end
    local a,b=adapt715r_pair(c,'GetLocalScale')
    local px,py=adapt715r_pair(c,'GetAnchoredPosition')
    local tol=1e-5
    if a and b and px and py and math.abs(a-s)<tol and math.abs(b-s)<tol and math.abs(px-x)<tol and math.abs(py-y)<tol then
      return true
    end
    local ok=pcall(function()
      if not px or not py or math.abs(px-x)>=tol or math.abs(py-y)>=tol then c:SetAnchoredPosition(x,y) end
      if not a or not b or math.abs(a-s)>=tol or math.abs(b-s)>=tol then c:SetLocalScale(s,s,1) end
    end)
    a,b=adapt715r_pair(c,'GetLocalScale')
    px,py=adapt715r_pair(c,'GetAnchoredPosition')
    return ok and a and b and px and py and math.abs(a-s)<eps and math.abs(b-s)<eps and math.abs(px-x)<eps and math.abs(py-y)<eps
  end`
);

patch(
  'sync_adapt715r撕边591叶缓存与选关卡字号按需刷新',
  String.raw`  -- 撕边组已重挂到art641.select末尾；显隐逐叶处理，不依赖父级级联。
  for _,v in ipairs(ADAPT715R_TEARS) do
    local group=find(v.name)
    if group then
      set_visible(group,page=='select')
      pcall(function() group:SetAsLastSibling() end)
      local good,children=pcall(function() return group:GetChildren() end)
      if good and type(children)=='table' then
        for _,child in ipairs(children) do set_visible(child,page=='select') end
      end
    end
    local sign=v.side=='tr' and 1 or -1
    transform(v.name,adapt14_corner(w,h,v.side))
  end
  if cardsOk then
    if adapter._select715_scale~=cardScale or adapter._select715_gen~=gen then
      adapter._select715_scale=cardScale;adapter._select715_gen=gen
      local cur=Murdoku.current();local controller=cur and cur.controller
      if controller then controller.dirty=true;controller._props={} end
    end
    -- 正文属性可能被翻页重新写入；依据当前文字重算字号，不从上次字号累乘。
    for i=1,4 do
      for _,suffix in ipairs({'info','title','result'}) do
        local c=find('select.card.'..i..'.'..suffix)
        if c then pcall(function()
          local size=16*cardScale
          if suffix~='result' then
            local units=0;for ch in tostring(c.text or ''):gmatch('[%z\1-\127\194-\244][\128-\191]*') do units=units+(#ch==1 and .55 or 1) end
            size=math.min(18,math.max(10,math.floor((182-6)/math.max(1,units))))*cardScale
          end
          c.adaptiveFontSize=false;c.minimumFontSize=size;c.fontSize=size
        end) end
      end
    end
  end`,
  String.raw`  -- 撕边组已重挂到art641.select末尾；显隐逐叶处理，不依赖父级级联（744：按代缓存子叶与状态）。
  st.tearKids=st.tearKids or {}; st.tearState=st.tearState or {}
  for _,v in ipairs(ADAPT715R_TEARS) do
    local group=find(v.name)
    if group then
      local gok=set_visible(group,selecting)
      local kids=st.tearKids[v.name]
      if not kids then
        local good,children=pcall(e744_get_kids,group)
        if good and type(children)=='table' and #children>0 then kids=children; st.tearKids[v.name]=kids end
      end
      if force or st.tearState[v.name]~=selecting then
        if selecting then pcall(e744_last_sib,group) end
        local done=gok
        if kids then
          for i=1,#kids do done=set_visible(kids[i],selecting) and done end
        else
          done=false
        end
        if done then st.tearState[v.name]=selecting end
      end
    end
    transform(v.name,adapt14_corner(w,h,v.side))
  end
  if cardsOk then
    if adapter._select715_scale~=cardScale or adapter._select715_gen~=gen then
      adapter._select715_scale=cardScale;adapter._select715_gen=gen
      st.cardFont={}
      local cur=Murdoku.current();local controller=cur and cur.controller
      if controller then controller.dirty=true;controller._props={} end
    end
    -- 正文属性可能被翻页重新写入；仅在选关页按文本+缩放与当前字号脏检查重算字号。
    if selecting or force then
      st.cardFont=st.cardFont or {}
      for i=1,4 do
        for _,suffix in ipairs({'info','title','result'}) do
          local cname='select.card.'..i..'.'..suffix
          local c=find(cname)
          if c then
            local ok_t, txt = pcall(e744_get_k, c, 'text')
            if ok_t then
              local fkey=tostring(txt or '')..'|'..tostring(cardScale)
              local rec=st.cardFont[cname]
              local ok_fs, cur_fs = pcall(e744_get_k, c, 'fontSize')
              if force or rec==nil or rec.key~=fkey or not ok_fs or cur_fs~=rec.size then
                local size=16*cardScale
                if suffix~='result' then
                  local units=0;for ch in tostring(txt or ''):gmatch('[%z\1-\127\194-\244][\128-\191]*') do units=units+(#ch==1 and .55 or 1) end
                  size=math.min(18,math.max(10,math.floor((182-6)/math.max(1,units))))*cardScale
                end
                local ok_w=pcall(function()
                  c.adaptiveFontSize=false;c.minimumFontSize=size;c.fontSize=size
                end)
                if ok_w then st.cardFont[cname]={key=fkey,size=size} end
              end
            end
          end
        end
      end
    end
  end`
);

// ── 13. sync_econ742：签名未变且非 force 时跳过每 0.25s 的 4 次重复写入 ─────
patch(
  'sync_econ742稳态早退',
  `  -- 保持中心锚定：上部按键自然内收，下部按钮也有等量余地。
  local applied=pcall(function()
    if group.SetLocalScale then group:SetLocalScale(scale,scale,1) end
    if group.SetAnchoredPosition then group:SetAnchoredPosition(0,0) end
    if group.SetVisible then group:SetVisible(active) end
    if group.SetActive then group:SetActive(active) end
  end)
  local signature=table.concat({page,cw,ch,scale,tostring(active)},'/')
  if applied and st.signature~=signature then
    st.signature=signature
    print('[econ742] '..signature)
  end`,
  `  local signature=table.concat({page,cw,ch,scale,tostring(active)},'/')
  if not force and not pageChanged and st.applied_sig==signature and st.applied_group==group then return end
  -- 保持中心锚定：上部按键自然内收，下部按钮也有等量余地。
  local applied=pcall(function()
    if group.SetLocalScale then group:SetLocalScale(scale,scale,1) end
    if group.SetAnchoredPosition then group:SetAnchoredPosition(0,0) end
    if group.SetVisible then group:SetVisible(active) end
    if group.SetActive then group:SetActive(active) end
  end)
  if applied then
    st.applied_sig=signature; st.applied_group=group
    if st.signature~=signature then
      st.signature=signature
      print('[econ742] '..signature)
    end
  end`
);

// ── 14. 更新构建标记 ────────────────────────────────────────────────────────
const marker = '构建标记 v743 / 全面性能优化';
assert(lua.includes(marker), '未找到 743 构建标记');
lua = lua.replaceAll(marker, '构建标记 v744 / 深度运行时优化');

// ── 语法与冷启动回归检查 ────────────────────────────────────────────────────
fs.mkdirSync(temp, { recursive: true });
const candPath = path.join(temp, 'candidate744.lua');
fs.writeFileSync(candPath, lua);

const syntax = spawnSync('lua', ['-e', "assert(load(io.read('*a'))); print('SYNTAX PASS')"], {
  input: lua, encoding: 'utf8', timeout: 30000,
});
assert.equal(syntax.status, 0, syntax.stderr || syntax.error?.message);
console.log(syntax.stdout.trim());

function cold(s) {
  const p = spawnSync('lua', [path.join(repo, 'tests/shop_cold_render.lua')], {
    input: s, encoding: 'utf8', timeout: 60000,
  });
  assert.equal(p.status, 0, p.stderr || p.error?.message);
  const m = p.stdout.match(/COLD=(\d+) WRITES=(\d+) COLD_FINDS=(\d+) FINDS=(\d+)/);
  assert(m, p.stdout);
  return m.slice(1).map(Number);
}
const before = cold(original);
const after = cold(lua);
assert.deepEqual(after, before, 'shop_cold_render 属性写入/查找回归不匹配');
console.log('COLD 743', before, '744', after);

const stats = {
  baseVersion: '743',
  baseSha256: sha(g.src),
  baseBytes: g.src.length,
  scriptBytesBefore: Buffer.byteLength(original),
  scriptBytesAfter: Buffer.byteLength(lua),
  candidateSha256: sha(Buffer.from(lua)),
  patches,
  cold: { before, after },
  records: g.recs.length,
};

if (isCandidate) {
  fs.writeFileSync(path.join(temp, 'candidate744_stats.json'), JSON.stringify(stats, null, 2));
  console.log('CANDIDATE OK', candPath, 'patches=', patches.length, 'sha256=', stats.candidateSha256);
  process.exit(0);
}

const validationArg = process.argv.find((a) => a.startsWith('--validation='));
const validationPath = validationArg
  ? path.resolve(validationArg.slice(13))
  : path.join(temp, 'validation744.json');
assert(fs.existsSync(validationPath), '缺少独立验证报告：' + validationPath);
const validationFile = JSON.parse(fs.readFileSync(validationPath, 'utf8'));
const validation = validationFile.validation || validationFile;
assert.equal(validation.candidateSha256, stats.candidateSha256, '验证报告与当前候选脚本 SHA256 不一致');
assert.equal(validation.pass, true, '独立验证未通过');

leaf.field.payload = Buffer.from(lua);
leaf.field.len = leaf.field.payload.length;
leaf.field.sub = null;

fs.mkdirSync(path.dirname(out), { recursive: true });
const recordBytes = new Map(g.recs.map((r) => [r.id, encodeMsg([r.field])]));
const report = writeGil(g, out, {
  label: '744 深度运行时优化',
  expectDiffs: 1,
  expectMarker: 'v744',
  expectRecs: g.recs.length,
  assert(saved) {
    assert(findScriptLeaf(saved).buf.equals(Buffer.from(lua)), '重读脚本与写入不一致');
    assert(saved.trailer.equals(g.trailer), 'trailer 不一致');
    for (const r of saved.recs) {
      assert(encodeMsg([r.field]).equals(recordBytes.get(r.id)), '控件记录发生意外变化: ' + r.name);
    }
    return true;
  },
});

fs.writeFileSync(path.join(path.dirname(out), '744_内嵌脚本.lua'), lua);
fs.writeFileSync(path.join(path.dirname(out), '744_性能与验证.json'), JSON.stringify({
  ...stats,
  outputBytes: report.bytes,
  outputSha256: sha(report.g2.src),
  controlRecordsChanged: 0,
  fieldDifferences: report.diffs,
  validation,
  limits: [
    '性能与等价验证基于导出自 743.gil 的 8,578 节点真实控件树离线模拟，非真机实测帧率',
    '保留全部 pcall 保护、迟到控件自愈（首秒敏感 + 稳态指数退避）、换屏/换关重建清缓存和 X 标记 70%/底图点亮逻辑',
    '744 以 tools/build_744.mjs 与 744_内嵌脚本.lua 为派生链，未改动任何 .gil 控件记录',
  ],
}, null, 2));
console.log('OUTPUT', out, report.bytes, sha(report.g2.src));
