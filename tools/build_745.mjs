// 745：从 744_深度运行时优化.gil 派生，仅修改内嵌 Lua，不覆盖基准或旧存档。
// 解禁 11 条历史性能优化禁区，在严格保障全部核心玩法/UI/交互/容错能力的前提下，
// 深度压低切屏峰值卡顿、稳态每帧 CPU/API/pcall/GC 开销，并修正 adapt715r.WAX.12 与 pagers 的双写抖动。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { loadTree, findScriptLeaf, writeGil } from './gil/gilwrite.mjs';
import { encodeMsg } from './gil/gilread.mjs';

const repo = fileURLToPath(new URL('../', import.meta.url));
const temp = process.env.FEIBO_TMP || 'C:/Users/18182/AppData/Local/Temp/feibo/94ca8342-2ce8-485b-9984-8dc46fb543d3';
const out = path.resolve(process.argv[2] && !process.argv[2].startsWith('--')
  ? process.argv[2]
  : path.join(repo, '745_解禁全面优化/745_解禁全面优化.gil'));
const base = path.join(repo, '744_深度运行时优化/744_深度运行时优化.gil');
const isCandidate = process.argv.includes('--candidate');
if (!isCandidate) assert(!fs.existsSync(out), '输出已存在，拒绝覆盖：' + out);

const sha = (b) => createHash('sha256').update(b).digest('hex');
const g = loadTree(base);
const leaf = findScriptLeaf(g);
const original = leaf.buf.toString('utf8');
assert.equal(sha(g.src), '166694ef198d33fce1c76a4e4fa6c7ab6d02e76502bb6879f4d9102500798ee7', '基准 744 SHA256 不匹配');

let lua = original;
const patches = [];
function patch(tag, before, after) {
  const parts = lua.split(before);
  assert.equal(parts.length, 2, `补丁不唯一或未命中 [${tag}] (matches=${parts.length - 1})`);
  lua = lua.replace(before, () => after);
  patches.push(tag);
}

// ── 1. 清理 Controller:_grid_render 历史空转循环 + _find_by_name 复用已建索引免裸 DFS ──
patch(
  '_grid_render删空转诊断循环',
  `  self._grid_sig = sig
  if not self._tpl_logged and print then
    self._tpl_logged = true
    for _, nm in ipairs({ "clue", "clues.grid", "clues" }) do
      local c = nil
      pcall(function() c = self:_find_by_name(nm) end)
    end
  end
  self._grid_state = "on"`,
  `  self._grid_sig = sig
  self._tpl_logged = true
  self._grid_state = "on"`
);

patch(
  '_find_by_name复用适配器全树索引并去闭包',
  `function Controller:_find_by_name(name)
  if name == nil then return nil end
  local hit = nil
  -- 655: 先复用 adapter 的精确路径/名字索引与缓存，避免另起一趟全树 DFS。
  if self.adapter ~= nil and self.adapter.find ~= nil then
    pcall(function() hit = self.adapter:find(name) end)
    if hit ~= nil then return hit end
  end
  local search = nil
  search = function(x, d)
    if hit ~= nil or x == nil or d > 6 then return end
    local nm = nil
    pcall(function() nm = tostring(x.name) end)
    if nm == name then hit = x return end
    local ks = nil
    pcall(function() ks = x:GetChildren() end)
    if ks ~= nil then
      local n = 0
      pcall(function() n = #ks end)
      for i = 1, n do search(ks[i], d + 1) end
    end
  end
  local roots = nil
  pcall(function() roots = game.GetClientUIRoots() end)
  if roots ~= nil then
    local rn = 0
    pcall(function() rn = #roots end)
    for i = 1, rn do search(roots[i], 0) end
  end
  return hit
end`,
  `local function c745_name(x) return x.name end
local function c745_kids(x) return x:GetChildren() end
function Controller:_find_by_name(name)
  if name == nil then return nil end
  local ad = self.adapter
  if ad ~= nil and ad.find ~= nil then
    local ok, hit = pcall(ad.find, ad, name)
    if ok and hit ~= nil then return hit end
    -- 745：若适配器本代数全树索引有效且已建立，缺项即为不存在，不再重复跑 9,788 节点裸 DFS。
    if ad._name_idx ~= nil and ad._name_idx_gen == ad._lookup_gen and (ad._name_idx_nodes or 0) > 0 then
      return nil
    end
  end
  local hit = nil
  local function search(x, d)
    if hit ~= nil or x == nil or d > 6 then return end
    local ok_n, nm = pcall(c745_name, x)
    if ok_n and nm == name then hit = x return end
    local ok_k, ks = pcall(c745_kids, x)
    if ok_k and type(ks) == "table" then
      for i = 1, #ks do search(ks[i], d + 1) end
    end
  end
  local ok_r, roots = pcall(game.GetClientUIRoots)
  if ok_r and type(roots) == "table" then
    for i = 1, #roots do search(roots[i], 0) end
  end
  return hit
end`
);

// ── 2. 网格视窗热路径去匿名闭包 + 合并 pcall（保留禁区 5/6/7/8/10/11 全部功能）──
patch(
  '_grid_refill_now与gray去闭包',
  `function Controller:_grid_refill_now(adapter, grid)
  if grid == nil then return 0 end
  local seen = self._grid_seen
  if seen == nil then return 0 end
  local n = 0
  self._grid_in_refresh = false           
  for item, idx in pairs(seen) do
    pcall(function() self:_fill_grid_item(adapter, grid, item, idx) end)
    n = n + 1
  end
  self._grid_in_refresh = false
  return n
end
function Controller:_grid_disable_gray_raycast(item, index, pos)
  local cg = self:_grid_item_child_cached(item, index, pos, "gray")
  if cg == nil then return false end
  local rec = self:_grid_item_rec(item, index)
  if rec ~= nil and rec.gray_noray == true then return true end
  if rec ~= nil then rec.gray_noray = true end
  if cg.raycastTarget ~= nil then pcall(function() cg.raycastTarget = false end) end
  if cg.blockRaycast ~= nil then pcall(function() cg.blockRaycast = false end) end
  if cg.interactable ~= nil then pcall(function() cg.interactable = false end) end
  return true
end`,
  `local function c745_disable_gray(cg)
  if cg.raycastTarget ~= nil and cg.raycastTarget ~= false then cg.raycastTarget = false end
  if cg.blockRaycast ~= nil and cg.blockRaycast ~= false then cg.blockRaycast = false end
  if cg.interactable ~= nil and cg.interactable ~= false then cg.interactable = false end
end
function Controller:_grid_refill_now(adapter, grid)
  if grid == nil then return 0 end
  local seen = self._grid_seen
  if seen == nil then return 0 end
  local n = 0
  self._grid_in_refresh = false
  for item, idx in pairs(seen) do
    pcall(self._fill_grid_item, self, adapter, grid, item, idx)
    n = n + 1
  end
  self._grid_in_refresh = false
  return n
end
function Controller:_grid_disable_gray_raycast(item, index, pos)
  local cg = self:_grid_item_child_cached(item, index, pos, "gray")
  if cg == nil then return false end
  local rec = self:_grid_item_rec(item, index)
  if rec ~= nil and rec.gray_noray == true then return true end
  if rec ~= nil then rec.gray_noray = true end
  pcall(c745_disable_gray, cg)
  return true
end`
);

// ── 3. Controller:_render_impl：切屏探活快速通道（保留重建自动兜底）+ 去闭包 ──
patch(
  '_render_impl切屏探活复用与去闭包',
  `    if self._tree_screen ~= self.screen or self._tree_level ~= lv_id then
      self._tree_screen = self.screen
      self._tree_level = lv_id
      if adapter and adapter.clear_board_portraits then adapter:clear_board_portraits() end
      self._props = {}  
      if adapter ~= nil and adapter.invalidate_lookups ~= nil then
        pcall(function()
          adapter:invalidate_lookups("screen=" .. tostring(self.screen)
            .. " level=" .. tostring(lv_id))
        end)
      end
      if adapter ~= nil and adapter.rearm_raycast ~= nil then
        pcall(function()
          adapter:rearm_raycast("screen=" .. tostring(self.screen)
            .. " level=" .. tostring(lv_id))
        end)
      end
      if adapter ~= nil and adapter.rearm_cursor ~= nil then
        pcall(function()
          adapter:rearm_cursor("screen=" .. tostring(self.screen)
            .. " level=" .. tostring(lv_id))
        end)
      end
    end`,
  `    if self._tree_screen ~= self.screen or self._tree_level ~= lv_id then
      local level_changed745 = (self._tree_level ~= lv_id)
      self._tree_screen = self.screen
      self._tree_level = lv_id
      if adapter and adapter.clear_board_portraits then adapter:clear_board_portraits() end
      self._props = {}
      local why745 = "screen=" .. tostring(self.screen) .. " level=" .. tostring(lv_id)
      -- 745（解禁禁区3）：同关普通切屏先 O(1) 探活当前 root 句柄；仅在关卡变更或 root 句柄确实失效重建时才全量清缓存并重扫射线/光标。
      local tree_alive745 = false
      if not level_changed745 and adapter ~= nil and adapter._root_alive745 ~= nil then
        local ok_a, alive = pcall(adapter._root_alive745, adapter)
        tree_alive745 = (ok_a and alive == true)
      end
      if not tree_alive745 then
        if adapter ~= nil and adapter.invalidate_lookups ~= nil then
          pcall(adapter.invalidate_lookups, adapter, why745)
        end
        if adapter ~= nil and adapter.rearm_raycast ~= nil then
          pcall(adapter.rearm_raycast, adapter, why745)
        end
        if adapter ~= nil and adapter.rearm_cursor ~= nil then
          pcall(adapter.rearm_cursor, adapter, why745)
        end
      else
        -- 树未重建：清掉未命中节流以便新页迟到控件立即重查，保留全部有效句柄，0 全树 DFS / 0 全树射线重扫！
        adapter._misses = nil
        adapter._miss_streak = nil
        adapter._mark_layer_dirty745 = true
      end
    end`
);

// ── 4. Adapter 静态零闭包/合并 pcall 助手 + _root_alive745 + root 缓存 ──────────
patch(
  'Adapter合并pcall助手与root探活',
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
  self._lookup_gen = (self._lookup_gen or 0) + 1`,
  `local function p744_name(c) return c.name end
local function p744_kids(c) return c:GetChildren() end
local function p744_child(c, k) return c:GetChild(k) end
local function p744_vis(c) return c.visible end
local function p744_set_vis(c, v) c:SetVisible(v) end
local function p744_ray_get(c) return c.raycastTarget end
local function p744_ray_set(c, v) c.raycastTarget = v end
local function p744_cur_set(c) if c.showCursor ~= true then c.showCursor = true end end
local function p744_field(c, k) return c[k] end
local function p745_set_vis_guard(c, want)
  if want then
    if c.SetActive ~= nil and c.active ~= true then c:SetActive(true) end
  end
  if c.SetVisible ~= nil and c.visible ~= want then c:SetVisible(want) end
end
local function p745_set_ray_guard(c, want)
  if c.raycastTarget ~= nil and c.raycastTarget ~= want then c.raycastTarget = want end
  if c.blockRaycast ~= nil and c.blockRaycast ~= want then c.blockRaycast = want end
  if c.interactable ~= nil and c.interactable ~= want then c.interactable = want end
end
local function p745_set_vis_false(c)
  if c.SetVisible ~= nil then
    if c.visible ~= false then c:SetVisible(false) end
  elseif c.SetActive ~= nil then
    if c.active ~= false then c:SetActive(false) end
  end
end
local function p745_last_sib(c) c:SetAsLastSibling() end
local function p745_index_node(c) return c.name, c:GetChildren() end
local function p745_ray_step(c, want)
  local before = c.raycastTarget
  local did = false
  if before ~= nil and before ~= want then
    c.raycastTarget = want
    did = true
  end
  return before, did, c:GetChildren()
end
local path745_root_cache = {}
function Adapter:_root_alive745()
  local r = self.controls and self.controls["root"]
  if r == nil then return false end
  local ok_n, nm = pcall(p744_name, r)
  if not ok_n or nm ~= "root" then return false end
  if game == nil or game.GetClientUIRoots == nil then return true end
  local ok_r, roots = pcall(game.GetClientUIRoots)
  if not ok_r or type(roots) ~= "table" then return false end
  for i = 1, #roots do
    if roots[i] == r then return true end
  end
  return false
end
function Adapter:invalidate_lookups(why)
  self._misses = nil
  self._miss_streak = nil
  self._name_idx_stable = 0
  self._floor_slots = nil
  self._floor_faces = nil
  self._floor_layout = nil
  self.controls = {}
  self.subs = {}
  self._sub_miss = nil
  self._mark_layer = nil
  self._mark_ctl_cache = nil
  self._mark_layer_dirty745 = true
  self._ray_done_gen745 = nil
  self._subtree_dirty = true
  self._subtree_dirty_ids = nil
  self._baked_dirty = true
  path745_root_cache = {}
  self._lookup_gen = (self._lookup_gen or 0) + 1`
);

// index_in 合并 2 次 pcall 为 1 次（仍带双保险降级，保留禁区 2 容错）
patch(
  'index_in合并单次pcall',
  `local function index_in(ctrl, depth, idx, n)
  if ctrl == nil or depth > 16 then return n end
  n = n + 1
  local ok, cname = pcall(p744_name, ctrl)
  if ok and cname ~= nil and idx[cname] == nil then idx[cname] = ctrl end
  local okc, children = pcall(p744_kids, ctrl)
  if okc and type(children) == "table" then
    for i = 1, #children do n = index_in(children[i], depth + 1, idx, n) end
  end
  return n
end`,
  `local function index_in(ctrl, depth, idx, n)
  if ctrl == nil or depth > 16 then return n end
  n = n + 1
  local ok, cname, children = pcall(p745_index_node, ctrl)
  if not ok then
    ok, cname = pcall(p744_name, ctrl)
    local okc; okc, children = pcall(p744_kids, ctrl)
    if not okc then children = nil end
  end
  if ok and cname ~= nil and idx[cname] == nil then idx[cname] = ctrl end
  if type(children) == "table" then
    for i = 1, #children do n = index_in(children[i], depth + 1, idx, n) end
  end
  return n
end`
);

// ── 5. path_lookup_655：缓存 route[1] 根容器句柄 + 合并链式 GetChild 为单次 pcall ──
patch(
  'path_lookup_655缓存根容器与单pcall链式查',
  `  for i = 1, #roots do
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
  end
  return nil
end`,
  `  local function walk_route745(start, r, want)
    local cur = start
    for k = 2, #r do
      cur = cur:GetChild(r[k])
      if cur == nil then return nil end
    end
    if cur ~= nil and cur.name == want then return cur end
    return nil
  end
  local r0_name = route[1]
  local cached_root = path745_root_cache[r0_name]
  if cached_root ~= nil then
    local ok_c, hit_c = pcall(walk_route745, cached_root, route, name)
    if ok_c and hit_c ~= nil then return hit_c end
    local ok_n, rn = pcall(p744_name, cached_root)
    if not ok_n or rn ~= r0_name then
      path745_root_cache[r0_name] = nil
    else
      -- 根句柄仍有效但该子路径不存在，不必再扫其余 100+ 顶层模板根！
      return nil
    end
  end
  for i = 1, #roots do
    local cur = roots[i]
    local ok, rn = pcall(p744_name, cur)
    if ok and rn == r0_name then
      path745_root_cache[r0_name] = cur
      local ok_w, hit = pcall(walk_route745, cur, route, name)
      if ok_w and hit ~= nil then return hit end
    end
  end
  return nil
end`
);

// ── 6. Adapter:enable_raycast（解禁禁区 3 & 2）：单趟收敛 + 合并单节点 pcall + 仅增量 ──
patch(
  'enable_raycast单趟收敛与合并pcall',
  `local RAY_IDLE_STOP = 3       
local RAY_MAX_SCANS = 25      
function Adapter:rearm_raycast(why)
  local st = self._ray
  if st == nil then return end
  if st.scans == 0 and not st.done then return end     
  st.scans, st.idle, st.done = 0, 0, false
  if self.cfg and self.cfg.debug_raycast and print then
    print(PREFIX .. "射线开关：重新开始扫描（" .. tostring(why) .. "）")
  end
end
function Adapter:ensure_raycast(c)
  if c == nil then return false end
  local before = nil
  pcall(function() before = c.raycastTarget end)
  if before == nil then return false end           
  if before == true then return true end           
  local ok = pcall(function() c.raycastTarget = true end)
  return ok == true
end
function Adapter:enable_raycast()
  local st = self._ray
  if st == nil then
    st = { scans = 0, idle = 0, done = false, seen = 0, set = 0, announced = false }
    self._ray = st
  end
  if st.done then return st.seen, st.set, {} end
  local root = self:find("root")
  if root == nil then return 0, 0, {} end
  local set, seen, samples = 0, 0, {}
  local visited = {}
  local function walk(c, depth)
    if c == nil or depth > 20 or visited[c] then return end
    visited[c] = true
    -- 699：显式关闭的装饰层射线不能被全局扫描重新打开。
    local want = not (self._ray_want and self._ray_want[c] == false)
    local ok_b, before = pcall(p744_ray_get, c)
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
    if not ok_k then kids = nil end
    if type(kids) == "table" then
      for i = 1, #kids do walk(kids[i], depth + 1) end
    end
  end
  walk(root, 0)
  st.scans = st.scans + 1
  st.seen, st.set = seen, set
  if seen > 0 and set == 0 then st.idle = st.idle + 1 else st.idle = 0 end
  if seen > 0 and st.idle >= RAY_IDLE_STOP then`,
  `local RAY_IDLE_STOP = 1
local RAY_MAX_SCANS = 25
function Adapter:rearm_raycast(why)
  local st = self._ray
  if st == nil then return end
  if st.scans == 0 and not st.done then return end
  st.scans, st.idle, st.done = 0, 0, false
  if self.cfg and self.cfg.debug_raycast and print then
    print(PREFIX .. "射线开关：重新开始扫描（" .. tostring(why) .. "）")
  end
end
function Adapter:ensure_raycast(c)
  if c == nil then return false end
  local ok_b, before = pcall(p744_ray_get, c)
  if not ok_b or before == nil then return false end
  if before == true then return true end
  local ok = pcall(p744_ray_set, c, true)
  return ok == true
end
function Adapter:enable_raycast()
  local st = self._ray
  if st == nil then
    st = { scans = 0, idle = 0, done = false, seen = 0, set = 0, announced = false }
    self._ray = st
  end
  if st.done then return st.seen, st.set, {} end
  local root = self:find("root")
  if root == nil then return 0, 0, {} end
  local set, seen, samples = 0, 0, {}
  local visited = {}
  local ray_want = self._ray_want
  local function walk(c, depth)
    if c == nil or depth > 20 or visited[c] then return end
    visited[c] = true
    -- 699：显式关闭的装饰层射线不能被全局扫描重新打开；745 合并单节点读/写/取子为单次 pcall。
    local want = not (ray_want and ray_want[c] == false)
    local ok, before, did, kids = pcall(p745_ray_step, c, want)
    if not ok then
      local ok_b; ok_b, before = pcall(p744_ray_get, c)
      if not ok_b then before = nil end
      did = false
      if before ~= nil and before ~= want then
        did = pcall(p744_ray_set, c, want) == true
      end
      local ok_k; ok_k, kids = pcall(p744_kids, c)
      if not ok_k then kids = nil end
    end
    if before ~= nil then
      seen = seen + 1
      if did then
        set = set + 1
        if #samples < 6 then
          local ok_n, nm = pcall(p744_name, c)
          samples[#samples + 1] = (ok_n and tostring(nm) or "?") .. ":" .. tostring(before) .. "->true"
        end
      end
    end
    if type(kids) == "table" then
      for i = 1, #kids do walk(kids[i], depth + 1) end
    end
  end
  walk(root, 0)
  st.scans = st.scans + 1
  st.seen, st.set = seen, set
  -- 745：若首趟就已把本树全部节点的 raycastTarget 设齐（set > 0 或 set == 0），1 趟零变更即收敛，避免再连扫 3 趟 6,138 节点。
  if seen > 0 and set == 0 then st.idle = st.idle + 1 else st.idle = 0 end
  if seen > 0 and (st.idle >= RAY_IDLE_STOP or (st.scans == 1 and set > 0)) then`
);

// ── 7. Adapter:_mark_layer_raise 事件驱动脏标记 + 关内 60 帧兜底（非关内 0 次） ──
patch(
  '_mark_layer_raise事件驱动与低频兜底',
  `function Adapter:_mark_layer_raise()
  local m = self._mark_layer
  if m == nil then
    m = self:find("art685.mark.overlay")
    if m == nil then return end
    self._mark_layer = m
  end
  if m.SetAsLastSibling ~= nil then
    -- 689：缓存闭包，避免每帧新建函数对象；685「每帧复位」不变式完全保留
    if self._mark_raise_target ~= m then
      self._mark_raise_target = m
      self._mark_raise_fn = function() m:SetAsLastSibling() end
    end
    pcall(self._mark_raise_fn)
  end
end`,
  `function Adapter:_mark_layer_raise(force)
  local m = self._mark_layer
  if m == nil then
    m = self:find("art685.mark.overlay")
    if m == nil then return end
    self._mark_layer = m
    self._mark_layer_dirty745 = true
  end
  if force == false and not self._mark_layer_dirty745 then return end
  self._mark_layer_dirty745 = false
  if m.SetAsLastSibling ~= nil then
    pcall(p745_last_sib, m)
  end
end`
);

patch(
  'on_tick按需置顶mark_layer',
  `function Adapter:on_tick(dt)
  self.clock = self.clock + (dt or 0)
  -- ★ 685：每帧复位标记层 ⇒ 未来任何新的抬格代码都自动被覆盖，无需再改层序
  self:_mark_layer_raise()`,
  `function Adapter:on_tick(dt)
  self.clock = self.clock + (dt or 0)
  -- 745：事件驱动复位标记层（抬格/建格/重建时已即时置顶）；关内每 60 帧兜底复核一次，非关内 0 次。
  self._mark_tick745 = (self._mark_tick745 or 0) + 1
  if self._mark_layer_dirty745 or (self._mark_screen_on == true and (self._mark_tick745 % 60 == 0)) then
    self:_mark_layer_raise(true)
  end`
);

// ── 8. Adapter:set_property & destroy_control & _mark_* 写前读回守卫与去闭包 ──
patch(
  'destroy_control读回守卫去闭包',
  `  if ctrl ~= nil then
    if ctrl.SetVisible then
      pcall(function() ctrl:SetVisible(false) end)
    elseif ctrl.SetActive then
      pcall(function() ctrl:SetActive(false) end)
    end
  end`,
  `  if ctrl ~= nil then
    pcall(p745_set_vis_false, ctrl)
  end`
);

patch(
  '_mark_hide_all与_mark_set_visible读回守卫去闭包',
  `function Adapter:_mark_hide_all()
  local t = self:_mark_all_ctrls()
  for i = 1, #t do
    local q = t[i]
    if q.SetVisible ~= nil then pcall(function() q:SetVisible(false) end) end
  end
  self._mark_screen_on = false
end`,
  `function Adapter:_mark_hide_all()
  if self._mark_screen_on == false and self._mark_all_hidden_gen745 == self._lookup_gen then return end
  local t = self:_mark_all_ctrls()
  for i = 1, #t do
    pcall(p745_set_vis_false, t[i])
  end
  self._mark_screen_on = false
  if #t >= 192 then self._mark_all_hidden_gen745 = self._lookup_gen end
end`
);

patch(
  '_mark_set_visible读回守卫去闭包',
  `function Adapter:_mark_set_visible(rc, on)
  -- ★ 686：关卡外一律不点亮（防止切屏瞬间 x_mark 抢先下发把 X 又打开）
  if on == true and self._mark_screen_on == false then on = false end
  local base = "art685.mark." .. rc
  local names = { base, base .. ".stroke.0", base .. ".stroke.1" }
  for i = 1, #names do
    local c = self:find(names[i])
    if c ~= nil and c.SetVisible then pcall(function() c:SetVisible(on) end) end
  end
end`,
  `function Adapter:_mark_set_visible(rc, on)
  -- ★ 686：关卡外一律不点亮（防止切屏瞬间 x_mark 抢先下发把 X 又打开）
  if on == true and self._mark_screen_on == false then on = false end
  if on then self._mark_all_hidden_gen745 = nil end
  local base = "art685.mark." .. rc
  local c0 = self:find(base); if c0 ~= nil then pcall(p745_set_vis_guard, c0, on) end
  local c1 = self:find(base .. ".stroke.0"); if c1 ~= nil then pcall(p745_set_vis_guard, c1, on) end
  local c2 = self:find(base .. ".stroke.1"); if c2 ~= nil then pcall(p745_set_vis_guard, c2, on) end
end`
);

patch(
  'set_property_image与visible与raycast写前读回守卫去闭包',
  `        if target.SetVisible then pcall(function() target:SetVisible(true) end) end`,
  `        pcall(p745_set_vis_guard, target, true)`
);

patch(
  'set_property_visible主写入读回守卫合并pcall',
  `    if value == true and ctrl.SetActive ~= nil then
      pcall(function() ctrl:SetActive(true) end)
    end
    local vis = value and true or false
    if ctrl.SetVisible then pcall(p744_set_vis, ctrl, vis) end`,
  `    local vis = value and true or false
    pcall(p745_set_vis_guard, ctrl, vis)`
);

patch(
  'set_property_hide_kids与raycast读回守卫去闭包',
  `      local function hide_kids(node, depth)
        if node == nil or depth > 4 then return end
        local kids = nil
        pcall(function() kids = node:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil then
              if k.SetVisible then pcall(function() k:SetVisible(false) end) end
              local nm = nil
              pcall(function() nm = k.name end)
              if nm ~= "furn" and nm ~= "rug_layer" and nm ~= "board.floors" and nm ~= "board.rugs" and nm ~= "x" then hide_kids(k, depth + 1) end  
            end
          end
        end
      end
      hide_kids(ctrl, 0)
    end
    if vis == true and id:sub(1, 5) == "cell." then
      local face = nil
      pcall(function() face = self:sub(id, "face") end)
      if face ~= nil and face.SetVisible ~= nil then
        pcall(function() face:SetVisible(true) end)
      end
      local w = (self._edge_want ~= nil) and self._edge_want[id] or nil
      if w ~= nil then
        for name, want in pairs(w) do
          local s2 = self:sub(id, name)
          if s2 ~= nil and s2.SetVisible ~= nil then
            pcall(function() s2:SetVisible(want) end)
          end
        end
      end
    end
  elseif key == "raycast" then
    local want = value and true or false
    self._ray_want = self._ray_want or setmetatable({}, { __mode = "k" })
    self._ray_want[ctrl] = want
    if ctrl.raycastTarget ~= nil then
      pcall(function() ctrl.raycastTarget = want end)
    end
    if ctrl.blockRaycast ~= nil then
      pcall(function() ctrl.blockRaycast = want end)
    end
    if ctrl.interactable ~= nil then
      pcall(function() ctrl.interactable = want end)
    end`,
  `      local function hide_kids(node, depth)
        if node == nil or depth > 4 then return end
        local ok_k, kids = pcall(p744_kids, node)
        if ok_k and type(kids) == "table" then
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil then
              pcall(p745_set_vis_false, k)
              local ok_n, nm = pcall(p744_name, k)
              if not ok_n or (nm ~= "furn" and nm ~= "rug_layer" and nm ~= "board.floors" and nm ~= "board.rugs" and nm ~= "x") then
                hide_kids(k, depth + 1)
              end
            end
          end
        end
      end
      hide_kids(ctrl, 0)
    end
    if vis == true and id:sub(1, 5) == "cell." then
      local ok_f, face = pcall(self.sub, self, id, "face")
      if ok_f and face ~= nil then pcall(p745_set_vis_guard, face, true) end
      local w = (self._edge_want ~= nil) and self._edge_want[id] or nil
      if w ~= nil then
        for name, want in pairs(w) do
          local s2 = self:sub(id, name)
          if s2 ~= nil then pcall(p745_set_vis_guard, s2, want) end
        end
      end
    end
  elseif key == "raycast" then
    local want = value and true or false
    self._ray_want = self._ray_want or setmetatable({}, { __mode = "k" })
    self._ray_want[ctrl] = want
    pcall(p745_set_ray_guard, ctrl, want)`
);

// select_render_content 写前读回守卫（避免已对齐的选关缩略图重复下发 6 个 transform setter）
patch(
  'select_render_content读回守卫',
  `    if select_render_content(id) then
      -- 原型可能带 NaN 缩放，写 text/size 不会修复它。所有 setter 都必须成功。
      if not (finite_number(w) and finite_number(h) and finite_number(cx)
          and finite_number(cy) and finite_number(pcx) and finite_number(pcy)) then return false end
      local ok, err = pcall(function()
        ctrl:SetLocalScale(1, 1, 1)
        ctrl:SetAnchorMin(0.5, 0.5)
        ctrl:SetAnchorMax(0.5, 0.5)
        ctrl:SetPivot(0.5, 0.5)
        ctrl:SetSizeDelta(w, h)
        ctrl:SetAnchoredPosition(cx - pcx, cy - pcy)
      end)`,
  `    if select_render_content(id) then
      -- 原型可能带 NaN 缩放，写 text/size 不会修复它。所有 setter 都必须成功。
      if not (finite_number(w) and finite_number(h) and finite_number(cx)
          and finite_number(cy) and finite_number(pcx) and finite_number(pcy)) then return false end
      local function near0(a, b) return finite_number(a) and math.abs(a - b) < 0.01 end
      local rw0, rh0 = read_pair(ctrl, "GetSizeDelta")
      local rx0, ry0 = read_pair(ctrl, "GetAnchoredPosition")
      local sx0, sy0 = read_pair(ctrl, "GetLocalScale")
      if near0(rw0, w) and near0(rh0, h) and near0(rx0, cx - pcx) and near0(ry0, cy - pcy)
         and near0(sx0, 1) and near0(sy0, 1) then
        local aminx0, aminy0 = read_pair(ctrl, "GetAnchorMin")
        local amaxx0, amaxy0 = read_pair(ctrl, "GetAnchorMax")
        local px0, py0 = read_pair(ctrl, "GetPivot")
        if near0(aminx0, 0.5) and near0(aminy0, 0.5) and near0(amaxx0, 0.5) and near0(amaxy0, 0.5)
           and near0(px0, 0.5) and near0(py0, 0.5) then
          return true
        end
      end
      local ok, err = pcall(function()
        ctrl:SetLocalScale(1, 1, 1)
        ctrl:SetAnchorMin(0.5, 0.5)
        ctrl:SetAnchorMax(0.5, 0.5)
        ctrl:SetPivot(0.5, 0.5)
        ctrl:SetSizeDelta(w, h)
        ctrl:SetAnchoredPosition(cx - pcx, cy - pcy)
      end)`
);

// ── 9. CURSOR_CONTAINERS & key_control_fallbacks 清理历史废弃名 ───────────────
patch(
  'CURSOR_CONTAINERS清理历史废弃名',
  `local CURSOR_CONTAINERS = {
  "root", "topbar", "left", "tray", "clues", "board",
  "right", "actions", "modal",
  "home", "select",
}`,
  `local CURSOR_CONTAINERS = {
  "root", "topbar", "clues",
  "right", "modal", "home",
}`
);

patch(
  'key_control_fallbacks清理历史废弃board与bind_keyboard退避',
  `    key_control = "root",
    key_control_fallbacks = { "board", "cell.1.1", "topbar" },`,
  `    key_control = "root",
    key_control_fallbacks = { "stage", "cell.1.1", "topbar" },`
);

patch(
  'OnUpdate键盘重绑退避防移动端永久空转',
  `  if started and registration_clock>=2 then
    registration_clock=0
    local session=Murdoku.current()
    if session then session.retry_signals() end
    if adapter then
      if not keyboard_bound then bind_keyboard_once('重试') end
      for id,node in pairs(adapter._retry_input or {}) do adapter:bind_input(id,node) end
    end
  end`,
  `  if started and registration_clock>=2 then
    registration_clock=0
    local session=Murdoku.current()
    if session then session.retry_signals() end
    if adapter then
      if not keyboard_bound then
        local kt = (adapter._kb_retry745 or 0) + 1
        adapter._kb_retry745 = kt
        -- 745：移动端无 AddKeyEventListener 时前 3 次每 2s 重试，之后退避至每 30s 复核一次，避免无意义扫描。
        if kt <= 3 or (kt % 15 == 0) then bind_keyboard_once('重试') end
      end
      local in_lv745 = session and session.controller and (session.controller.screen == nil or session.controller.screen == "level")
      for id,node in pairs(adapter._retry_input or {}) do
        if in_lv745 or (type(id) ~= "string") or id:sub(1, 5) ~= "cell." then
          adapter:bind_input(id,node)
        end
      end
    end
  end`
);

patch(
  'tutorial_furniture防缺失board无限触发全树重扫',
  `  local parent = self:_find(self.root_name .. ".board")
  if parent == nil then
    self:_note("家具实例化跳过 tag=" .. self.tag .. "：找不到 " .. self.root_name .. ".board")
    return
  end`,
  `  local parent = self:_find(self.root_name .. ".board")
  if parent == nil then
    self._furn_skip_gen745 = self.adapter and self.adapter._lookup_gen or 0
    if not self._furn_skip_logged745 then
      self._furn_skip_logged745 = true
      self:_note("家具实例化跳过 tag=" .. self.tag .. "：找不到 " .. self.root_name .. ".board")
    end
    return
  end`
);

patch(
  'tutorial_furniture_done同代跳过缺失board',
  `function M:furniture_done()
  local spec = FURN[self.tag]
  if spec == nil then return true end
  if self.furniture == nil then return false end
  for i = 1, #spec do if self.furniture[i] == nil then return false end end
  return true
end`,
  `function M:furniture_done()
  local spec = FURN[self.tag]
  if spec == nil then return true end
  local cur_gen = self.adapter and self.adapter._lookup_gen or 0
  if self._furn_skip_gen745 == cur_gen then return true end
  if self.furniture == nil then return false end
  for i = 1, #spec do if self.furniture[i] == nil then return false end end
  return true
end`
);

patch(
  'read_pair与_furn_resync去闭包和读回守卫',
  `local function read_pair(ctrl, method)
  local ok, x, y = pcall(function() return ctrl[method](ctrl) end)
  if not ok then return nil, nil end
  if type(x) == "table" then return x.x or x[1], x.y or x[2] end
  return x, y
end`,
  `local function p745_read_pair(ctrl, method)
  local x, y = ctrl[method](ctrl)
  if type(x) == "table" then return x.x or x[1], x.y or x[2] end
  return x, y
end
local function read_pair(ctrl, method)
  local ok, x, y = pcall(p745_read_pair, ctrl, method)
  if not ok then return nil, nil end
  return x, y
end`
);

patch(
  'Adapter_sub去闭包与_furn_resync稳态降频',
  `  if parent.GetChild ~= nil then
    pcall(function() hit = parent:GetChild(child_name) end)
  end`,
  `  if parent.GetChild ~= nil then
    local ok_g, res_g = pcall(p744_child, parent, child_name)
    if ok_g then hit = res_g end
  end`
);

patch(
  '_furn_resync稳态退避',
  `  if self._furn_want ~= nil and next(self._furn_want) ~= nil and self._furn_level ~= false then
    if (self._furn_resync_at or -1) <= self.clock then
      self._furn_resync_at = self.clock + 0.5
      pcall(function() self:_furn_resync() end)
    end
  end`,
  `  if self._furn_want ~= nil and next(self._furn_want) ~= nil and self._furn_level ~= false then
    if (self._furn_resync_at or -1) <= self.clock then
      local fs = math.min(4, (self._furn_resync_streak745 or 0) + 1)
      self._furn_resync_streak745 = fs
      self._furn_resync_at = self.clock + (fs >= 3 and 4.0 or 0.5)
      pcall(self._furn_resync, self)
    end
  end`
);

// ── 10. Levels.all 静态结果缓存 + Murdoku.on_update 不再每帧调 Levels.all() ──
patch(
  'Levels.all缓存静态模块列表',
  `function M.all()
  M._errors = {}
  local out = {}
  for i = 1, #LIST do
    local ok, lv = pcall(__require, LIST[i])
    if ok and type(lv) == "table" then
      out[#out + 1] = lv
    else
      note_error(LIST[i], lv)
    end
  end
  return out
end`,
  `local _all_cache745 = nil
function M.all()
  if _all_cache745 ~= nil then return _all_cache745 end
  M._errors = {}
  local out = {}
  for i = 1, #LIST do
    local ok, lv = pcall(__require, LIST[i])
    if ok and type(lv) == "table" then
      out[#out + 1] = lv
    else
      note_error(LIST[i], lv)
    end
  end
  if #out == #LIST then _all_cache745 = out end
  return out
end`
);

patch(
  'on_update缓存n_levels与stage去闭包',
  `  do
    local n_levels = 8
    do
      local ok, all = pcall(Levels.all)
      if ok and type(all) == "table" and #all > 0 then n_levels = #all end
    end
    local widgets_on = not (current.adapter.cfg and current.adapter.cfg.widgets == false)
    local on_select = (scr_now == "select") and widgets_on
    do
      local s = nil
      pcall(function() s = current.adapter:find("stage") end)
      if s ~= nil then
        local sv = nil
        pcall(function() sv = s.visible end)
        if sv ~= true then pcall(function() s:SetVisible(true) end) end
        local sw0, sh0 = nil, nil
        if s ~= nil and print and current._stage_rb_logged ~= true then
          current._stage_rb_logged = true
          pcall(function() sw0, sh0 = s:GetSizeDelta() end)
          print("[murdoku] ★ 棋盘容器 stage 回读 " .. tostring(sw0) .. "x" .. tostring(sh0)
            .. "（★ 归编辑器 ✓ 脚本不再写它 ✓）")
        end
      end
      local bar = nil
      if on_select then pcall(function() bar = current.adapter:find("selbar") end) end
      if bar ~= nil then
        if on_select then
          pcall(function() bar:SetAnchoredPosition(0, 0) end)
          pcall(function() bar:SetSizeDelta(1500, 700) end)
        end
      end
    end`,
  `  do
    local n_levels = Murdoku._n_levels745
    if n_levels == nil then
      n_levels = 8
      local ok, all = pcall(Levels.all)
      if ok and type(all) == "table" and #all > 0 then n_levels = #all end
      Murdoku._n_levels745 = n_levels
    end
    local widgets_on = not (current.adapter.cfg and current.adapter.cfg.widgets == false)
    local on_select = (scr_now == "select") and widgets_on
    do
      local ad0 = current.adapter
      local s = ad0.controls and ad0.controls["stage"] or nil
      if s == nil then
        local ok_s, res_s = pcall(ad0.find, ad0, "stage")
        if ok_s then s = res_s end
      end
      if s ~= nil then
        local ok_sv, sv = pcall(m744_vis_get, s)
        if not ok_sv or sv ~= true then pcall(m744_vis_set, s, true) end
        if print and current._stage_rb_logged ~= true then
          current._stage_rb_logged = true
          local sw0, sh0 = nil, nil
          pcall(function() sw0, sh0 = s:GetSizeDelta() end)
          print("[murdoku] ★ 棋盘容器 stage 回读 " .. tostring(sw0) .. "x" .. tostring(sh0)
            .. "（★ 归编辑器 ✓ 脚本不再写它 ✓）")
        end
      end
      local bar = nil
      if on_select then
        local ok_b, res_b = pcall(ad0.find, ad0, "selbar")
        if ok_b then bar = res_b end
      end
      if bar ~= nil and on_select then
        pcall(function() bar:SetAnchoredPosition(0, 0) end)
        pcall(function() bar:SetSizeDelta(1500, 700) end)
      end
    end`
);

// ── 11. murdoku_set_vis 读回守卫 + 稳态 30 帧复核（消除每帧 24 次 find 与 60 帧无效写）──
patch(
  'murdoku_set_vis读回守卫与稳态降频',
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
end`,
  `local function m744_vis_get(c) return c.visible end
local function m744_vis_set(c, v) c:SetVisible(v) end
local function m745_vis_sync(c, want)
  if c.visible == want then return false end
  c:SetVisible(want)
  return true
end
local function murdoku_set_vis(ad, nm, want, forcing, memo)
  if ad == nil then return 0 end
  local c = ad.controls and ad.controls[nm] or nil
  if c == nil then
    -- 745：若已确认为同代缺失项，跳过每帧 pcall(ad.find) 开销。
    local misses = ad._misses
    if misses ~= nil then
      local stamp = misses[nm]
      if stamp == false or (type(stamp) == "number" and (ad.clock or 0) < stamp) then return 0 end
    end
    local ok_f, res_f = pcall(ad.find, ad, nm)
    if ok_f then c = res_f end
  end
  if c == nil then return 0 end
  local ok_w, did = pcall(m745_vis_sync, c, want)
  if ok_w then
    memo[nm] = want
    return did and 1 or 0
  end
  return 0
end`
);

patch(
  'on_update_murdoku_vis稳态降频与去冗余查找',
  `    do
      local STAGE_BG_ID   = 106053
      local STAGE_BG_TINT = 0xFF2C2820    
      local STAGE_BG_FALLBACK_ID = 107003
      local in_level = (scr_now == "level")
      local s = nil
      pcall(function() s = current.adapter:find("stage") end)`,
  `    do
      local STAGE_BG_ID   = 106053
      local STAGE_BG_TINT = 0xFF2C2820    
      local STAGE_BG_FALLBACK_ID = 107003
      local in_level = (scr_now == "level")
      local ad1 = current.adapter
      local s = ad1.controls and ad1.controls["stage"] or nil
      if s == nil then
        local ok_s1, res_s1 = pcall(ad1.find, ad1, "stage")
        if ok_s1 then s = res_s1 end
      end`
);

patch(
  'on_update_vis_ids稳态30帧复核',
  `      local vis_ids = murdoku_vis_ids
      if vis_ids ~= nil then
        for i = 1, #vis_ids do
          local nm = vis_ids[i]
          local want
          if nm == "tpl-container" then
            want = false
          elseif nm:sub(1, 5) == "cell." then
            want = true
          else
            want = in_select
          end
          wrote = wrote + murdoku_set_vis(ad_vis, nm, want, forcing, murdoku_vis_memo)
        end
      end`,
  `      local vis_ids = murdoku_vis_ids
      -- 745：换屏窗口内每帧检查，稳态后每 30 帧兜底复核一次，消除每帧 32 次冗余遍历。
      if vis_ids ~= nil and (forcing or (fnow % 30 == 0)) then
        for i = 1, #vis_ids do
          local nm = vis_ids[i]
          local want
          if nm == "tpl-container" then
            want = false
          elseif nm:sub(1, 5) == "cell." then
            want = true
          else
            want = in_select
          end
          wrote = wrote + murdoku_set_vis(ad_vis, nm, want, forcing, murdoku_vis_memo)
        end
      end`
);

// ── 12. 解禁禁区 4：关内 30 帧 face 点亮 + x 70% 缩放按代缓存句柄 + 读回守卫 + 稳态降频 ──
patch(
  '禁区4_face与x按代缓存句柄单pcall读回守卫',
  `    if scr_now == "level" and ((current.frames or 0) % 30) == 0 then
      local rows, cols = 5, 5
      pcall(function()
        local a = current.adapter
        if a ~= nil then
          rows = a.cells_rows or (a.cfg and a.cfg.cells and a.cfg.cells.rows) or rows
          cols = a.cells_cols or (a.cfg and a.cfg.cells and a.cfg.cells.cols) or cols
        end
      end)
      local n = 0
      for r = 1, rows do
        for c = 1, cols do
          local cid = "cell." .. r .. "." .. c
          local cell = nil
          pcall(function() cell = current.adapter:find(cid) end)
          local cw, ch = 124, 124
          if cell ~= nil then
            pcall(function()
              local a, b = cell:GetSizeDelta()
              if type(a) == "table" then cw, ch = a.x, a.y else cw, ch = a, b end
            end)
          end
          local face = nil
          if cell ~= nil and cell.GetChildren ~= nil then
            local kids = nil
            pcall(function() kids = cell:GetChildren() end)
            for _, k in ipairs(kids or {}) do
              local kn = nil
              pcall(function() kn = tostring(k.name) end)
              if kn == "content" or kn == "middle" or kn == "body" or kn == "root" then
                local cv = nil
                pcall(function() cv = k.visible end)
                if cv ~= true then pcall(function() k:SetVisible(true) end) end
                local cgw, cgh = nil, nil
                pcall(function() cgw, cgh = k:GetSizeDelta() end)
                if not (cgw == cw and cgh == ch) then
                  pcall(function() k:SetSizeDelta(cw, ch) end)
                end
                local cgx, cgy = nil, nil
                pcall(function() cgx, cgy = k:GetAnchoredPosition() end)
                if not (cgx == 0 and cgy == 0) then
                  pcall(function() k:SetAnchoredPosition(0, 0) end)
                end
              end
              if kn == "face" then
                local fv = nil
                pcall(function() fv = k.visible end)
                if fv ~= true then pcall(function() k:SetVisible(true) end) end
                local fgw, fgh = nil, nil
                pcall(function() fgw, fgh = k:GetSizeDelta() end)
                if not (fgw == cw and fgh == ch) then
                  pcall(function() k:SetSizeDelta(cw, ch) end)
                end
                local fgx, fgy = nil, nil
                pcall(function() fgx, fgy = k:GetAnchoredPosition() end)
                if not (fgx == 0 and fgy == 0) then
                  pcall(function() k:SetAnchoredPosition(0, 0) end)
                end
                face = k
              end
    if kn == "x" then
      local xw, xh = nil, nil
      pcall(function() xw, xh = k:GetSizeDelta() end)
      if not (xw == cw * 0.7 and xh == ch * 0.7) then
        pcall(function() k:SetSizeDelta(cw * 0.7, ch * 0.7) end)
      end
      local xx, xy = nil, nil
      pcall(function() xx, xy = k:GetAnchoredPosition() end)
      if not (xx == 0 and xy == 0) then
        pcall(function() k:SetAnchoredPosition(0, 0) end)
      end
    end
              if face == nil and k.GetChildren ~= nil then
                local kk = nil
                pcall(function() kk = k:GetChildren() end)
                for _, c2 in ipairs(kk or {}) do
                  local cn = nil
                  pcall(function() cn = tostring(c2.name) end)
                  if cn == "face" then
                    local gv = nil
                    pcall(function() gv = c2.visible end)
                    if gv ~= true then pcall(function() c2:SetVisible(true) end) end    
                    local ggw, ggh = nil, nil
                    pcall(function() ggw, ggh = c2:GetSizeDelta() end)
                    if not (ggw == cw and ggh == ch) then
                      pcall(function() c2:SetSizeDelta(cw, ch) end)
                    end
                    local ggx, ggy = nil, nil
                    pcall(function() ggx, ggy = c2:GetAnchoredPosition() end)
                    if not (ggx == 0 and ggy == 0) then
                      pcall(function() c2:SetAnchoredPosition(0, 0) end)
                    end
                    face = c2
    elseif cn == "x" then
      local zxw, zxh = nil, nil
      pcall(function() zxw, zxh = c2:GetSizeDelta() end)
      if not (zxw == cw * 0.7 and zxh == ch * 0.7) then
        pcall(function() c2:SetSizeDelta(cw * 0.7, ch * 0.7) end)
      end
      local zxx, zxy = nil, nil
      pcall(function() zxx, zxy = c2:GetAnchoredPosition() end)
      if not (zxx == 0 and zxy == 0) then
        pcall(function() c2:SetAnchoredPosition(0, 0) end)
      end
                  end
                end
              end
            end
          end
          if face ~= nil then
            pcall(function() face:SetVisible(true) end)
            n = n + 1
          end
        end
      end
      if n > 0 and current._face_on ~= n then
        current._face_on = n
        if print then
          print("[murdoku] 格子底图已点亮：" .. tostring(n) .. " 个 face（每帧保持）")
        end
      end
    end`,
  `    if scr_now == "level" then
      local f745 = current.frames or 0
      local ad745 = current.adapter
      local gen745 = (ad745 and ad745._lookup_gen) or 0
      local fc745 = current._face_cache745
      if fc745 == nil or fc745.gen ~= gen745 then
        fc745 = { gen = gen745, stable = 0, cells = {} }
        current._face_cache745 = fc745
      end
      local step745 = (fc745.stable >= 2) and 120 or 30
      if (f745 % step745) == 0 then
        local rows, cols = 5, 5
        if ad745 ~= nil then
          rows = ad745.cells_rows or (ad745.cfg and ad745.cfg.cells and ad745.cfg.cells.rows) or rows
          cols = ad745.cells_cols or (ad745.cfg and ad745.cfg.cells and ad745.cfg.cells.cols) or cols
        end
        local function read_xy745(obj, method)
          local a, b = obj[method](obj)
          if type(a) == "table" then return a.x, a.y end
          return a, b
        end
        local function fit_box745(obj, want_vis, tw, th)
          local fixed = false
          if want_vis and obj.visible ~= true then obj:SetVisible(true); fixed = true end
          local gw, gh = read_xy745(obj, "GetSizeDelta")
          if gw ~= tw or gh ~= th then obj:SetSizeDelta(tw, th); fixed = true end
          local gx, gy = read_xy745(obj, "GetAnchoredPosition")
          if gx ~= 0 or gy ~= 0 then obj:SetAnchoredPosition(0, 0); fixed = true end
          return fixed
        end
        local function sync_cell745(rec)
          local cell = rec.cell
          local cw, ch = read_xy745(cell, "GetSizeDelta")
          cw, ch = cw or 124, ch or 124
          local fixed = false
          if rec.box ~= nil then
            local _ = rec.box.name
            if fit_box745(rec.box, true, cw, ch) then fixed = true end
          end
          if rec.face ~= nil then
            local _ = rec.face.name
            if fit_box745(rec.face, true, cw, ch) then fixed = true end
          end
          if rec.x ~= nil then
            local _ = rec.x.name
            if fit_box745(rec.x, false, cw * 0.7, ch * 0.7) then fixed = true end
          end
          return rec.face ~= nil, fixed
        end
        local n, any_fixed, all_ready = 0, false, true
        for r = 1, rows do
          for c = 1, cols do
            local cid = "cell." .. r .. "." .. c
            local rec = fc745.cells[cid]
            local cell = ad745 and ad745.controls and ad745.controls[cid] or nil
            if cell == nil and ad745 ~= nil then
              local ok_f, res_f = pcall(ad745.find, ad745, cid)
              if ok_f then cell = res_f end
            end
            if cell ~= nil then
              if rec == nil or rec.cell ~= cell or (rec.face == nil and (rec.probe745 or 0) < 2) then
                local probes = (rec ~= nil and rec.cell == cell) and ((rec.probe745 or 0) + 1) or 1
                rec = { cell = cell, probe745 = probes }
                pcall(function()
                  local kids = cell.GetChildren and cell:GetChildren() or nil
                  if type(kids) == "table" then
                    for _, k in ipairs(kids) do
                      local kn = tostring(k.name)
                      if kn == "content" or kn == "middle" or kn == "body" or kn == "root" then
                        rec.box = k
                      elseif kn == "face" then
                        rec.face = k
                      elseif kn == "x" then
                        rec.x = k
                      end
                      if (rec.face == nil or rec.x == nil) and k.GetChildren ~= nil then
                        local kk = k:GetChildren()
                        if type(kk) == "table" then
                          for _, c2 in ipairs(kk) do
                            local cn = tostring(c2.name)
                            if cn == "face" then rec.face = c2
                            elseif cn == "x" then rec.x = c2 end
                          end
                        end
                      end
                    end
                  end
                end)
                fc745.cells[cid] = rec
              end
              local ok_s, has_face, did_fix = pcall(sync_cell745, rec)
              if not ok_s then
                fc745.cells[cid] = nil
                all_ready = false
              else
                if has_face then n = n + 1 end
                if did_fix then any_fixed = true end
              end
            else
              all_ready = false
            end
          end
        end
        if all_ready and not any_fixed then
          fc745.stable = math.min(4, fc745.stable + 1)
        else
          fc745.stable = 0
        end
        if n > 0 and current._face_on ~= n then
          current._face_on = n
          if print then
            print("[murdoku] 格子底图已点亮：" .. tostring(n) .. " 个 face（每帧保持）")
          end
        end
      end
    end`
);

// ── 13. 教程探测去 "board" 废弃名 + 去闭包 + tick_hint635 常量表提升 + help_visible 单 pcall ──
patch(
  'tut_probe清理废弃board与去闭包_help_visible单pcall',
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
end
local function tutorial_home_visible()
  return tut_visible("home")
end
local TUT_PROBE_NAMES = { "home", "select.card.1", "select.title", "clues", "board" }    
local TUT_PREWARM_AFTER = 60  
local tut_prewarm_frames = 0
local tut_prewarm_done = false
local TUT_STABLE_NEED = 20    
local TUT_KEEP_NEED = 10      
local tut_key_prev = nil
local tut_key_frames = 0
local tut_shown_frames = 0
local tut_key_logged = false  
local tut_miss_frames = {}    
local function tut_key_and_probe()
  local cur = nil
  pcall(function()
    if Murdoku ~= nil and Murdoku.current ~= nil then cur = Murdoku.current() end
  end)
  if adapter ~= nil and adapter.prefetch ~= nil then
    pcall(function() adapter:prefetch(TUT_PROBE_NAMES) end)
  end
  local home  = tut_visible("home")
  local card1 = tut_visible("select.card.1")
  if not card1 then card1 = tut_visible("select.title") end    
  local clues = tut_visible("clues")
  local board = tut_visible("board")
  local scr, id = nil, nil
  if cur ~= nil then
    pcall(function() scr = cur.screen end)
    pcall(function() id = cur.level and cur.level.id end)
  end
  local key = nil
  if cur ~= nil then
    if home then
      key = "home"                        
    elseif card1 then
      key = nil                           
    elseif clues or board then
      if id ~= nil then key = tostring(id) end    
    end
  end
  return key, { home = home, card1 = card1, clues = clues, board = board, scr = scr, id = id }
end
local tut_last_probe = nil
local function current_tut_key()
  local key, probe = tut_key_and_probe()
  tut_last_probe = probe
  return key
end
local help617 = { bound = false, entry_bound = false, close_bound = false, open = false, overlay = false }
local function help_visible(c, v)
  if c == nil then return end
  local ok_v, actual = pcall(e744_vis, c)
  if not ok_v or actual ~= v then
    pcall(e744_set_vis, c, v)
  end
  if v then
    local ok_a, active = pcall(e744_act, c)
    if not ok_a or active ~= true then pcall(e744_set_act, c, true) end
  end
end`,
  `local function e744_vis(c) return c.visible end
local function e744_act(c) return c.active end
local function e744_set_vis(c, v) if c.SetVisible then c:SetVisible(v) else c.visible = v end end
local function e744_set_act(c, v) if c.SetActive then c:SetActive(v) end end
local function e744_last_sib(c) c:SetAsLastSibling() end
local function e744_get_kids(c) return c:GetChildren() end
local function e744_get_k(c, k) return c[k] end
local function e744_set_k(c, k, v) c[k] = v end
local function e745_help_vis(c, v)
  if c.visible ~= v then
    if c.SetVisible then c:SetVisible(v) else c.visible = v end
  end
  if v and c.active ~= true then
    if c.SetActive then c:SetActive(true) end
  end
end
local function e745_set_vis_pair(c, want)
  local a, v = c.active, c.visible
  if (a == want or v == want) and a ~= not want and v ~= not want then return true end
  local wrote = false
  if c.SetVisible and v ~= want then c:SetVisible(want); wrote = true end
  local a1 = c.active
  if c.SetActive and a1 ~= want then c:SetActive(want); wrote = true end
  local a2, v2 = c.active, c.visible
  return wrote and (a2 == want or v2 == want) and a2 ~= not want and v2 ~= not want
end
local function e745_pair(c, method)
  local x, y = c[method](c)
  if type(x) == "number" and type(y) == "number" then return x, y end
  if x ~= nil then return x.x or x.X, x.y or x.Y end
  return nil, nil
end
local function e745_transform(c, x, y, s, tol)
  local sx, sy = e745_pair(c, "GetLocalScale")
  local px, py = e745_pair(c, "GetAnchoredPosition")
  if sx and sy and px and py and math.abs(sx - s) < tol and math.abs(sy - s) < tol
     and math.abs(px - x) < tol and math.abs(py - y) < tol then
    return true
  end
  if not px or not py or math.abs(px - x) >= tol or math.abs(py - y) >= tol then c:SetAnchoredPosition(x, y) end
  if not sx or not sy or math.abs(sx - s) >= tol or math.abs(sy - s) >= tol then c:SetLocalScale(s, s, 1) end
  local a, b = e745_pair(c, "GetLocalScale")
  local rx, ry = e745_pair(c, "GetAnchoredPosition")
  return a and b and rx and ry and math.abs(a - s) < .002 and math.abs(b - s) < .002
     and math.abs(rx - x) < .002 and math.abs(ry - y) < .002
end
local function e745_set_pos(c, x, y) c:SetAnchoredPosition(x, y) end
local function e745_set_font(c, size) c.adaptiveFontSize = false; c.minimumFontSize = size; c.fontSize = size end
local function tut_visible(name)
  if adapter == nil or name == nil then return false end
  local c = adapter.controls and adapter.controls[name] or nil
  if c == nil then
    local ok_f, res_f = pcall(adapter.find, adapter, name)
    if not ok_f or res_f == nil then return false end
    c = res_f
  end
  local ok_v, v = pcall(e744_vis, c)
  return ok_v and v == true
end
local function tutorial_home_visible()
  return tut_visible("home")
end
-- 745：移除存档中已废弃不存在的 "board"（由 clues / stage 覆盖），根治每 1~16s 因永远 miss 触发的 8,578 节点全树重扫！
local TUT_PROBE_NAMES = { "home", "select.card.1", "select.title", "clues", "stage" }
local TUT_PREWARM_AFTER = 60  
local tut_prewarm_frames = 0
local tut_prewarm_done = false
local TUT_STABLE_NEED = 20    
local TUT_KEEP_NEED = 10      
local tut_key_prev = nil
local tut_key_frames = 0
local tut_shown_frames = 0
local tut_key_logged = false  
local tut_miss_frames = {}    
local tut_probe_buf745 = {}
local function tut_key_and_probe()
  local cur = (Murdoku ~= nil and Murdoku.current ~= nil) and Murdoku.current() or nil
  local home  = tut_visible("home")
  local card1 = tut_visible("select.card.1")
  if not card1 then card1 = tut_visible("select.title") end
  local clues = tut_visible("clues")
  local board = false
  local scr, id = nil, nil
  if cur ~= nil then
    scr = cur.screen
    local lv = cur.level
    if lv ~= nil then id = lv.id end
  end
  local key = nil
  if cur ~= nil then
    if home then
      key = "home"
    elseif card1 then
      key = nil
    elseif clues then
      if id ~= nil then key = tostring(id) end
    end
  end
  local p = tut_probe_buf745
  p.home, p.card1, p.clues, p.board, p.scr, p.id = home, card1, clues, board, scr, id
  return key, p
end
local tut_last_probe = nil
local function current_tut_key()
  local key, probe = tut_key_and_probe()
  tut_last_probe = probe
  return key
end
local help617 = { bound = false, entry_bound = false, close_bound = false, open = false, overlay = false }
local function help_visible(c, v)
  if c == nil then return end
  pcall(e745_help_vis, c, v)
end`
);

// ── 14. tick_hint635 常量表提升与稳态早退 ───────────────────────────────────
patch(
  'tick_hint635常量表与稳态早退',
  `local hint635_ui={}
local function tick_hint635()
  if not adapter then return end
  local util=tutorial_instance(TUT_SETS.l1)
  if not util then return end
  local gen=adapter._lookup_gen or 0
  if hint635_ui.generation~=gen then hint635_ui={generation=gen,controls={},bound={}} end
  local h=hint635_ui
  local names={"hint635.menu","hint635.result","hint635.menu.bg","hint635.menu.title",
    "hint635.menu.position","hint635.menu.clue","hint635.menu.close",
    "hint635.result.bg","hint635.result.body","hint635.result.close",
    "hint635.menu.position.hit","hint635.menu.clue.hit","hint635.menu.close.hit","hint635.result.close.hit"}
  for _,name in ipairs(names) do
    if not h.controls[name] then
      h.controls[name]=adapter:find(name)
      if h.controls[name] then help_visible(h.controls[name],name~="hint635.menu" and name~="hint635.result") end
    end
  end
  local cur=Murdoku.current()
  local ctrl=cur and cur.controller
  local actions={["hint635.menu.position.hit"]="position",["hint635.menu.clue.hit"]="clue",
    ["hint635.menu.close.hit"]="close",["hint635.result.close.hit"]="close"}
  for name,action in pairs(actions) do
    if not h.bound[name] and h.controls[name] then
      local chosen=action
      h.bound[name]=util:_bind(name,function()
        local c=Murdoku.current()
        if c and c.controller then c.controller:hint635_action(chosen); tick_hint635() end
      end,h.controls[name])
    end
  end
  if ctrl and (ctrl.screen~=nil or ctrl.modal~=nil or overlay_open()) then ctrl.hint635=nil end
  local state=ctrl and ctrl.hint635
  local signature=state and (state.kind..":"..(state.text or "")) or "closed"
  local used=ctrl and ctrl.core and ctrl.core.hint635_used or {position=0,clue=0}
  signature=signature..":"..tostring(used.position)..":"..tostring(used.clue)`,
  `local HINT635_NAMES={"hint635.menu","hint635.result","hint635.menu.bg","hint635.menu.title",
  "hint635.menu.position","hint635.menu.clue","hint635.menu.close",
  "hint635.result.bg","hint635.result.body","hint635.result.close",
  "hint635.menu.position.hit","hint635.menu.clue.hit","hint635.menu.close.hit","hint635.result.close.hit"}
local HINT635_ACTIONS={["hint635.menu.position.hit"]="position",["hint635.menu.clue.hit"]="clue",
  ["hint635.menu.close.hit"]="close",["hint635.result.close.hit"]="close"}
local HINT635_ZERO_USED={position=0,clue=0}
local hint635_ui={}
local function tick_hint635()
  if not adapter then return end
  local gen=adapter._lookup_gen or 0
  if hint635_ui.generation~=gen then hint635_ui={generation=gen,controls={},bound={},all_ready=false} end
  local h=hint635_ui
  if not h.all_ready then
    local util=tutorial_instance(TUT_SETS.l1)
    if not util then return end
    local ready=true
    for i=1,#HINT635_NAMES do
      local name=HINT635_NAMES[i]
      if not h.controls[name] then
        h.controls[name]=adapter:find(name)
        if h.controls[name] then help_visible(h.controls[name],name~="hint635.menu" and name~="hint635.result") else ready=false end
      end
    end
    for name,action in pairs(HINT635_ACTIONS) do
      if not h.bound[name] then
        if h.controls[name] then
          local chosen=action
          h.bound[name]=util:_bind(name,function()
            local c=Murdoku.current()
            if c and c.controller then c.controller:hint635_action(chosen); tick_hint635() end
          end,h.controls[name])
        end
        if not h.bound[name] then ready=false end
      end
    end
    h.all_ready=ready
  end
  local cur=Murdoku.current()
  local ctrl=cur and cur.controller
  if ctrl and (ctrl.screen~=nil or ctrl.modal~=nil or overlay_open()) then ctrl.hint635=nil end
  local state=ctrl and ctrl.hint635
  local used=ctrl and ctrl.core and ctrl.core.hint635_used or HINT635_ZERO_USED
  -- 745：关闭态且上次已同步为同控制器关闭态时零分配早退。
  if state==nil and h.closed_ok==true and h.controller==ctrl and h.closed_pos==used.position and h.closed_clue==used.clue then
    return
  end
  local signature=state and (state.kind..":"..(state.text or "")) or "closed"
  signature=signature..":"..tostring(used.position)..":"..tostring(used.clue)`
);

patch(
  'tick_hint635记录关闭态快路径',
  `  if h.signature~=signature or h.controller~=ctrl then
    h.signature=signature;h.controller=ctrl
    help_visible(h.controls["hint635.menu"],state~=nil and state.kind=="menu")`,
  `  if h.signature~=signature or h.controller~=ctrl then
    h.signature=signature;h.controller=ctrl
    h.closed_ok=(state==nil); h.closed_pos=used.position; h.closed_clue=used.clue
    help_visible(h.controls["hint635.menu"],state~=nil and state.kind=="menu")`
);

// ── 15. sync_block640 状态变化驱动（消除稳态每帧 3000 pcall 与 600 SetAsLastSibling）──
patch(
  'sync_block640状态驱动与零闭包',
  `    help_visible(panel, want)
    if want then
      pcall(function() panel.showCursor = true end)
      pcall(function() panel.disableCursorEventPassthrough = true end)
      pcall(function() panel:SetAsLastSibling() end)
      for _, target in ipairs(spec.targets) do
        local c = adapter:find(target)
        if c then pcall(function() c:SetAsLastSibling() end) end
      end
    end`,
  `    -- 745：按状态变化同步显隐与置顶（并在每 60 帧兜底确认一次），消除每帧无条件 SetAsLastSibling 与 10 次 pcall。
    local btick = (e.tick745 or 0) + 1
    e.tick745 = btick
    if e.last_want745 ~= want or (btick % 60 == 0) then
      help_visible(panel, want)
      if want and panel then
        pcall(e745_set_k_block640, panel)
        for ti = 1, #spec.targets do
          local c = adapter:find(spec.targets[ti])
          if c then pcall(e744_last_sib, c) end
        end
      end
      e.last_want745 = want
    end`
);

patch(
  'sync_block640辅助函数与confirm分支优化',
  `local block640_cache = nil
local block640_cache_gen = -1
local function sync_block640()`,
  `local function e745_set_k_block640(panel)
  if panel.showCursor ~= true then panel.showCursor = true end
  if panel.disableCursorEventPassthrough ~= true then panel.disableCursorEventPassthrough = true end
  panel:SetAsLastSibling()
end
local block640_cache = nil
local block640_cache_gen = -1
local function sync_block640()`
);

patch(
  'sync_block640_confirm分支状态驱动',
  `    elseif spec.tag == "confirm" then
      want = false
      help_visible(hit, false)
      if ctrl and ctrl.pending then
        for _, target in ipairs(spec.targets) do
          local button = adapter:find(target)
          if button then pcall(function() button:SetAsLastSibling() end) end
        end
      end`,
  `    elseif spec.tag == "confirm" then
      want = false
      local pend = ctrl and ctrl.pending or nil
      if e.hit_hidden745 ~= hit then
        help_visible(hit, false)
        e.hit_hidden745 = hit
      end
      if pend ~= nil and e.last_pend745 ~= pend then
        for ti = 1, #spec.targets do
          local button = adapter:find(spec.targets[ti])
          if button then pcall(e744_last_sib, button) end
        end
      end
      e.last_pend745 = pend`
);

// ── 16. sync_adapt715r：去闭包 + 修复 WAX.12 / pagers 乒乓双写 + 参数签名稳态早退 ──
patch(
  'adapt715r_pair去闭包',
  `local function adapt715r_pair(c,method)
  if c==nil then return nil end
  local ok,x,y=pcall(function() return c[method](c) end)
  if not ok then return nil end
  if type(x)=='number' and type(y)=='number' then return x,y end
  if x~=nil then local good,a,b=pcall(function() return x.x or x.X,x.y or x.Y end);if good then return a,b end end
end`,
  `local function adapt715r_pair(c,method)
  if c==nil then return nil end
  local ok,x,y=pcall(e745_pair,c,method)
  if not ok then return nil end
  return x,y
end`
);

patch(
  'sync_adapt715r_set_visible与签名早退与去WAX乒乓',
  `  local function set_visible(c,want)
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
  end
  local pageChanged=page~=st.page
  st.elapsed=st.elapsed+(dt or 0)
  if not force and not pageChanged and st.elapsed<.25 then return end
  st.elapsed=0
  local bg=find('adapt715r.background')
  local fill=find('adapt715r.background.fill')
  local base=find('art647.select.bg.base')
  local visible=set_visible(base,selecting)
  local bgWanted=page=='home' or page=='game'
  visible=set_visible(bg,bgWanted) and visible
  visible=set_visible(fill,page~='shop' and page~='bag') and visible
  if fill then pcall(function() fill.imageColor=selecting and ADAPT715R_SELECT_COLOR or ADAPT715R_HOME_COLOR end) end
  if bg and not st.leaves then
    local ok,children=pcall(function() return bg:GetChildren() end)
    if ok and type(children)=='table' and #children==649 then st.leaves=children;st.leafState=nil end
  end
  if st.leaves and (st.leafState~=bgWanted or force) then
    local done=true
    for _,c in ipairs(st.leaves) do done=set_visible(c,bgWanted) and done end
    if done then st.leafState=bgWanted end
  end
  st.page=page -- 控件延迟出现时，按 0.25 秒刷新重试。
  local ok,cw,ch=pcall(function() return game.GetUICanvasSize() end)
  local function valid(x) return type(x)=='number' and x>0 and x<math.huge end
  if not ok or not valid(cw) or not valid(ch) then return end
  local slot=adapt715r_device()
  local w,h=1600,1600*ch/cw
  if not valid(h) then return end
  adapter._adapt715_canvas={physical_w=cw,physical_h=ch,w=w,h=h,unit=1}
  cw,ch=w,h
  local fit=math.min(w/1600,h/900)
  local cover=fit -- 同步原版火漆父级与场景，不裁主体。
  local cardScale=adapt14_cards(w,h)
  local eps=.002
  local function transform(name,x,y,s)
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
  end
  local scene,shift=adapt14_background(w,h,transform,slot)
  local applied,missing,failed=0,0,0
  if slot~=nil then
    for _,t in ipairs(ADAPT715R_TARGETS) do
    local c=find(t.name)
    if c==nil then missing=missing+1 else
      local p=t.base[slot] or t.base[0]
      local x,y=p[1]+(t.ax-.5)*(w-1600),p[2]+(t.ay-.5)*(h-720)
      local sx,sy=1,1
      if t.kind=='WAX' then
        -- 火漆与整张背景保持独立父级；两棵树均以画布中心为原点。
        -- 子图元含相对背景中心的原始偏移，所以父级缩放同时变换位置与大小。
        sx,sy=cover,cover
        x,y=p[1]*cover,p[2]*cover
      end
      local good=pcall(function()
        local px,py=adapt715r_pair(c,'GetAnchoredPosition')
        if px==nil or math.abs(px-x)>eps or math.abs(py-y)>eps then c:SetAnchoredPosition(x,y) end
        if t.kind=='WAX' then
          local a,b=adapt715r_pair(c,'GetLocalScale')
          if a==nil or math.abs(a-sx)>eps or math.abs(b-sy)>eps then c:SetLocalScale(sx,sy,1) end
        end
      end)
      local px,py=adapt715r_pair(c,'GetAnchoredPosition')
      local scale_ok=true
      if t.kind=='WAX' then
        local a,b=adapt715r_pair(c,'GetLocalScale')
        scale_ok=a~=nil and math.abs(a-sx)<eps and math.abs(b-sy)<eps
      end
      if good and scale_ok and px and math.abs(px-x)<eps and math.abs(py-y)<eps then applied=applied+1 else failed=failed+1 end
    end
  end

  end
    transform('adapt715r.WAX.12',0,shift,scene)
  local pending = cur and cur.controller and cur.controller.pending
  if pending then follow_confirm717(find, pending.action) end`,
  `  local function set_visible(c,want)
    if not c then return false end
    local ok,matched=pcall(e745_set_vis_pair,c,want)
    return ok and matched
  end
  local pageChanged=page~=st.page
  st.elapsed=st.elapsed+(dt or 0)
  if not force and not pageChanged and st.elapsed<.25 then return end
  st.elapsed=0
  local ok_sz,cw,ch=pcall(game.GetUICanvasSize)
  local valid_sz=ok_sz and type(cw)=='number' and cw>0 and cw<math.huge and type(ch)=='number' and ch>0 and ch<math.huge
  local slot=valid_sz and adapt715r_device() or nil
  local pending=cur and cur.controller and cur.controller.pending
  local pend_act=pending and pending.action or ''
  local spage=(selecting and cur and cur.controller and cur.controller.select_page) or 0
  -- 745：若页面/画布尺寸/设备槽/控件树代/确认条/选关页码均未变且上一趟已全部就绪，直接早退！
  if not force and not pageChanged and valid_sz and st.steady_ok745==true
     and st.steady_cw==cw and st.steady_ch==ch and st.steady_slot==slot
     and st.steady_pend==pend_act and st.steady_spage==spage then
    return
  end
  local bg=find('adapt715r.background')
  local fill=find('adapt715r.background.fill')
  local base=find('art647.select.bg.base')
  local visible=set_visible(base,selecting)
  local bgWanted=page=='home' or page=='game'
  visible=set_visible(bg,bgWanted) and visible
  visible=set_visible(fill,page~='shop' and page~='bag') and visible
  if fill then
    local want_col=selecting and ADAPT715R_SELECT_COLOR or ADAPT715R_HOME_COLOR
    if st.fill_col745~=want_col or force then
      if pcall(e744_set_k,fill,'imageColor',want_col) then st.fill_col745=want_col end
    end
  end
  if bg and not st.leaves then
    local ok,children=pcall(e744_get_kids,bg)
    if ok and type(children)=='table' and #children==649 then st.leaves=children;st.leafState=nil end
  end
  if st.leaves and (st.leafState~=bgWanted or force) then
    local done=true
    for _,c in ipairs(st.leaves) do done=set_visible(c,bgWanted) and done end
    if done then st.leafState=bgWanted end
  end
  st.page=page -- 控件延迟出现时，按 0.25 秒刷新重试。
  if not valid_sz then return end
  local w,h=1600,1600*ch/cw
  if not (type(h)=='number' and h>0 and h<math.huge) then return end
  adapter._adapt715_canvas={physical_w=cw,physical_h=ch,w=w,h=h,unit=1}
  local phys_cw,phys_ch=cw,ch
  cw,ch=w,h
  local fit=math.min(w/1600,h/900)
  local cover=fit -- 同步原版火漆父级与场景，不裁主体。
  local cardScale=adapt14_cards(w,h)
  local eps=.002
  local function transform(name,x,y,s)
    local c=find(name)
    if not c then return false end
    local ok,matched=pcall(e745_transform,c,x,y,s,1e-5)
    return ok and matched
  end
  local scene,shift=adapt14_background(w,h,transform,slot)
  local applied,missing,failed=0,0,0
  if slot~=nil then
    for _,t in ipairs(ADAPT715R_TARGETS) do
      -- 745：WAX.12 与翻页器 4 控件紧随其后由专门公式写入最终位置/缩放，跳过先写旧值再覆盖导致的乒乓抖动与多余 SetPos/SetScale！
      local nm=t.name
      if nm=='adapt715r.WAX.12' or nm=='adapt715r.LM.19' or nm=='adapt715r.RM.20' or nm=='hit.select.prev' or nm=='hit.select.next' then
        if find(nm)==nil then missing=missing+1 else applied=applied+1 end
      else
        local c=find(nm)
        if c==nil then missing=missing+1 else
          local p=t.base[slot] or t.base[0]
          local x,y=p[1]+(t.ax-.5)*(w-1600),p[2]+(t.ay-.5)*(h-720)
          local px,py=adapt715r_pair(c,'GetAnchoredPosition')
          local good=true
          if px==nil or math.abs(px-x)>eps or math.abs(py-y)>eps then
            good=pcall(e745_set_pos,c,x,y)
            px,py=adapt715r_pair(c,'GetAnchoredPosition')
          end
          if good and px and math.abs(px-x)<eps and math.abs(py-y)<eps then applied=applied+1 else failed=failed+1 end
        end
      end
    end
  end
  local wax_ok=transform('adapt715r.WAX.12',0,shift,scene)
  if pending then follow_confirm717(find, pending.action) end`
);

patch(
  'sync_adapt715r写字号去闭包与记录稳态完成标记',
  `                local ok_w=pcall(function()
                  c.adaptiveFontSize=false;c.minimumFontSize=size;c.fontSize=size
                end)
                if ok_w then st.cardFont[cname]={key=fkey,size=size} end
              end
            end
          end
        end
      end
    end
  end

  local signature=table.concat({page,w,h,tostring(slot),tostring(st.leafState),tostring(visible),missing,failed},'/')`,
  `                local ok_w=pcall(e745_set_font,c,size)
                if ok_w then st.cardFont[cname]={key=fkey,size=size} end
              end
            end
          end
        end
      end
    end
  end

  local tears_done745=true
  for _,v in ipairs(ADAPT715R_TEARS) do
    if st.tearState[v.name]~=selecting then tears_done745=false; break end
  end
  st.steady_ok745=(visible==true and missing==0 and failed==0 and cardsOk==true and wax_ok==true and st.leafState==bgWanted and tears_done745)
  if st.steady_ok745 then
    st.steady_cw=phys_cw; st.steady_ch=phys_ch; st.steady_slot=slot
    st.steady_pend=pend_act; st.steady_spage=spage
  end
  local signature=table.concat({page,w,h,tostring(slot),tostring(st.leafState),tostring(visible),missing,failed},'/')`
);

patch(
  'sync_adapt715r_gen变更清理steady_ok745',
  `  if gen~=st.gen then st.handles={};st.gen=gen;st.leaves=nil;st.leafState=nil;st.tearKids={};st.tearState={};st.cardFont={};st.page=nil end`,
  `  if gen~=st.gen then st.handles={};st.gen=gen;st.leaves=nil;st.leafState=nil;st.tearKids={};st.tearState={};st.cardFont={};st.page=nil;st.steady_ok745=false;st.fill_col745=nil end`
);

// ── 16b. Tutorial:_find / _visible 读回守卫与零闭包（消除每帧 3 次 td.* 无效 SetVisible + 6 次闭包）──
patch(
  'Tutorial_find与_visible读回守卫去闭包',
  `function M:_find(name)
  local ctrl = nil
  pcall(function() ctrl = self.adapter:find(name) end)
  -- 700：名称索引可能早于教程子控件挂入；在已知根容器内补查，
  -- 不因每个迟到按钮重建全局索引，也不等待适配器时钟开始推进。
  if ctrl == nil and name ~= self.root_name then
    local root = nil
    pcall(function() root = self.adapter:find(self.root_name) end)
    if root ~= nil then
      pcall(function() ctrl = root:GetChild(name) end)
      if ctrl == nil then
        local kids = nil
        pcall(function() kids = root:GetChildren() end)
        if type(kids) == "table" then
          for _, child in ipairs(kids) do
            local actual = nil
            pcall(function() actual = child.name end)
            if actual == name then ctrl = child; break end
          end
        end
      end
    end
  end
  return ctrl
end
function M:_visible(name, want)
  local ctrl = self:_find(name)
  if ctrl == nil then return false end
  pcall(function() ctrl:SetVisible(want and true or false) end)
  if want then pcall(function() ctrl:SetActive(true) end) end
  return true
end`,
  `local function t745_find_in_root(root, name)
  local c = root:GetChild(name)
  if c ~= nil then return c end
  local kids = root:GetChildren()
  if type(kids) == "table" then
    for i = 1, #kids do
      local child = kids[i]
      if child ~= nil and child.name == name then return child end
    end
  end
  return nil
end
local function t745_set_vis(ctrl, want)
  if ctrl.visible ~= want then ctrl:SetVisible(want) end
  if want and ctrl.active ~= true then ctrl:SetActive(true) end
end
function M:_find(name)
  local ad = self.adapter
  if ad == nil or name == nil then return nil end
  local ctrl = ad.controls and ad.controls[name] or nil
  if ctrl == nil then
    local ok, res = pcall(ad.find, ad, name)
    if ok then ctrl = res end
  end
  -- 700：名称索引可能早于教程子控件挂入；在已知根容器内补查。
  if ctrl == nil and name ~= self.root_name then
    local root = ad.controls and ad.controls[self.root_name] or nil
    if root == nil then
      local ok_r, r = pcall(ad.find, ad, self.root_name)
      if ok_r then root = r end
    end
    if root ~= nil then
      local ok_c, c = pcall(t745_find_in_root, root, name)
      if ok_c then ctrl = c end
    end
  end
  return ctrl
end
function M:_visible(name, want)
  local ctrl = self:_find(name)
  if ctrl == nil then return false end
  pcall(t745_set_vis, ctrl, want and true or false)
  return true
end`
);

// ── 17. 版本标记更新为 v745 ──────────────────────────────────────────────────
patch(
  '版本标记v745_1',
  `if print then print("[murdoku] ===== 构建标记 v744 / 深度运行时优化 =====") end`,
  `if print then print("[murdoku] ===== 构建标记 v745 / 解禁全面优化 =====") end`
);
patch(
  '版本标记v745_2',
  `print("[murdoku] ===== 构建标记 v744 / 深度运行时优化 =====")`,
  `print("[murdoku] ===== 构建标记 v745 / 解禁全面优化 =====")`
);

// ── 校验 Lua 5.4 语法与冷启动回归 ──────────────────────────────────────────
fs.mkdirSync(temp, { recursive: true });
const candPath = path.join(temp, 'candidate745.lua');
fs.writeFileSync(candPath, lua, 'utf8');

const syn = spawnSync('lua', ['-e', `assert(load(assert(io.open([[${candPath}]], 'rb')):read('*a'), '@745')) print('SYNTAX PASS')`], { encoding: 'utf8' });
assert.equal(syn.status, 0, 'Lua 语法检查失败:\n' + syn.stderr + syn.stdout);
console.log(syn.stdout.trim());

function runCold(scriptText) {
  const r = spawnSync('lua', [path.join(repo, 'tests/shop_cold_render.lua')], { input: scriptText, encoding: 'utf8' });
  assert.equal(r.status, 0, 'shop_cold_render 失败:\n' + r.stderr + r.stdout);
  const m = r.stdout.match(/COLD=(\d+) WRITES=(\d+) COLD_FINDS=(\d+) FINDS=(\d+)/);
  assert(m, '未匹配到 COLD 输出：' + r.stdout);
  return m.slice(1).map(Number);
}

const coldBefore = runCold(original);
const coldAfter = runCold(lua);
console.log('COLD 744', coldBefore, '745', coldAfter);
assert.deepEqual(coldAfter, coldBefore, 'shop_cold_render 指标发生回归');

const stats = {
  baseVersion: '744',
  baseSha256: sha(g.src),
  baseBytes: g.src.length,
  scriptBytesBefore: Buffer.byteLength(original),
  scriptBytesAfter: Buffer.byteLength(lua),
  candidateSha256: sha(Buffer.from(lua)),
  patches,
  cold: { before: coldBefore, after: coldAfter },
  records: g.recs.length,
};

if (isCandidate) {
  console.log('CANDIDATE OK', candPath, 'patches=', patches.length, 'sha256=', stats.candidateSha256);
  process.exit(0);
}

// ── 正式产出：必须已有针对当前候选 SHA256 的独立验证报告 ────────────────────
const validationArg = process.argv.find((a) => a.startsWith('--validation='));
const validationPath = validationArg
  ? path.resolve(validationArg.slice(13))
  : path.join(temp, 'validation745.json');
assert(fs.existsSync(validationPath), '缺少独立验证结果：' + validationPath);
const validationFile = JSON.parse(fs.readFileSync(validationPath, 'utf8'));
const validation = validationFile.validation || validationFile;
assert.equal(validation.candidateSha256, stats.candidateSha256, '验证结果对应的候选 SHA256 不匹配');
assert.equal(validation.pass, true, '独立验证未通过');

leaf.field.payload = Buffer.from(lua);
leaf.field.len = leaf.field.payload.length;
leaf.field.sub = null;
fs.mkdirSync(path.dirname(out), { recursive: true });
const recordBytes = new Map(g.recs.map((r) => [r.id, encodeMsg([r.field])]));
const report = writeGil(g, out, {
  label: '745 解禁全面优化',
  expectDiffs: 1,
  expectMarker: 'v745',
  expectRecs: g.recs.length,
  assert(saved) {
    assert(findScriptLeaf(saved).buf.equals(Buffer.from(lua)), '重读脚本与候选不一致');
    assert(saved.trailer.equals(g.trailer), 'trailer 不一致');
    for (const r of saved.recs) {
      assert(encodeMsg([r.field]).equals(recordBytes.get(r.id)), '控件记录发生意外改动：' + r.name);
    }
    return true;
  },
});

fs.writeFileSync(path.join(path.dirname(out), '745_内嵌脚本.lua'), lua);
fs.writeFileSync(
  path.join(path.dirname(out), '745_性能与验证.json'),
  JSON.stringify(
    {
      ...stats,
      outputBytes: report.bytes,
      outputSha256: sha(report.g2.src),
      controlRecordsChanged: 0,
      fieldDifferences: report.diffs,
      validation,
      limits: [
        '性能与等价验证基于导出自真实 .gil 的 8,578 节点控件树离线模拟，非真机实测帧率',
        '解禁 11 条禁区限制后，保留全部核心玩法与容错：hex.back 唯一返回入口与确认条联动、单/批 pcall 异常兜底、root 探活失效自动回退全树重建、关内 face 恒亮与 x 70% 缩放、单射与 _row_face/_row_letter、gray 关射线与 RefreshItems 不清签名',
        '745 以 tools/build_745.mjs 与 745_内嵌脚本.lua 为派生链，未改动任何 .gil 控件记录',
      ],
    },
    null,
    2
  )
);
console.log('OUTPUT', out, report.bytes, sha(report.g2.src));
