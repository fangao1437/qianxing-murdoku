// 747：从 746_评审加固与切屏消峰.gil 派生，仅修改内嵌 Lua，不覆盖基准或旧存档。
// 响应提交 955ebd00434d《742 v13 至 746 性能优化独立评审》的全部 4 项 P1、4 项 P2、
// 商城缺项恢复等待优化、验证工程门禁加固，以及关内稳态/切屏进关最慢帧性能消峰：
//   P1-1：同根替换按钮（旧句柄仍可读、新同名按钮挂回）切屏当帧 + 2s 保活 O(1) 路径校验自动换绑与开射线；
//   P1-2：线索灰层写失败后玩家原地不动，通过 Controller:tick 0.25s→0.5s→1.0s 自动重试直至三属性全关；
//   P1-3：enable_raycast 遇读写/取子报错记录 errs 与失败节点，有错绝不收敛，下轮仅定向补扫失败子树；
//   P1-4：enforce_hidden_subtrees 失败项重新入队并 0.25s 节流重试，新切页隐藏立即执行，转可见自动撤队列；
//   P2-1：修复 cur_vis 未定义 bug（由 p745_set_vis_guard 返回写前可见状态）+ luac 字节码静态全局变量门禁；
//   P2-2：商城回读确认严格化，有写接口就要求对应读接口存在且回读命中目标值，读接口暂缺不锁死签名；
//   P2-3：格子巡检“完整”判定补齐 box（content/middle/body/root），确保 box/face/x 任一晚挂均能自动恢复；
//   P2-4：sync_adapt715r 拆分主布局稳态与翻页待重试项，翻页热区失败时仅定向重试失败的 1~4 项，零重跑整页；
//   Wait：静态路由缺失控件（econ.shop736.* 等）每 2.0s O(1) 轻量探活，挂回等待从 13.6s 压至 <= 2.0s（0 次整页空转）；
//   Perf-1：index_in 剪枝纯静态美术画片大容器（全部仍由 STATIC_PATH_655 O(1) 直查），全树索引节点从 8,578 降至 ~720；
//   Perf-2：murdoku_set_vis 关内稳态对 cell.* 走 O(1) stage/board 直查，消除稳态 17,156 次 GetChildren。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { loadTree, findScriptLeaf, writeGil } from './gil/gilwrite.mjs';
import { encodeMsg } from './gil/gilread.mjs';

const repo = fileURLToPath(new URL('../', import.meta.url));
const temp = process.env.FEIBO_TMP || 'C:/Users/18182/AppData/Local/Temp/feibo/f0aba3e7-9b70-48a6-8869-a73e908a6a1d';
const out = path.resolve(process.argv[2] && !process.argv[2].startsWith('--')
  ? process.argv[2]
  : path.join(repo, '747_交互闭环与尾部消峰/747_交互闭环与尾部消峰.gil'));
const base = path.join(repo, '746_评审加固与切屏消峰/746_评审加固与切屏消峰.gil');
const isCandidate = process.argv.includes('--candidate');
if (!isCandidate) assert(!fs.existsSync(out), '输出已存在，拒绝覆盖：' + out);

const sha = (b) => createHash('sha256').update(b).digest('hex');
const g = loadTree(base);
const leaf = findScriptLeaf(g);
const original = leaf.buf.toString('utf8');
assert.equal(sha(g.src), '86f343b5df3aa972976c8cfbeaa2698c0691291c626580b7d3924f759113f7d1', '基准 746 SHA256 不匹配');

let lua = original;
const patches = [];
function patch(tag, before, after) {
  const parts = lua.split(before);
  assert.equal(parts.length, 2, `补丁不唯一或未命中 [${tag}] (matches=${parts.length - 1})`);
  lua = lua.replace(before, () => after);
  patches.push(tag);
}

// ── 1. P1-2：线索灰层写失败后玩家原地不动自动定时重试 ──────────────────────
patch(
  'P1-2_Controller_tick原地重试未完成的灰层禁用',
  `  if self.toast ~= nil and self.toast_until ~= nil and self.now >= self.toast_until then
    self.toast = nil
    self.toast_until = nil
    self.dirty = true
  end`,
  `  if self.toast ~= nil and self.toast_until ~= nil and self.now >= self.toast_until then
    self.toast = nil
    self.toast_until = nil
    self.dirty = true
  end
  -- 747（P1-2）：若存在灰层禁用曾写失败的网格项，玩家原地不动也会按 0.25→0.5→1.0s 自动重试直至全关；正常成功时表为 nil（0 开销）。
  if self._grid_gray_retry747 ~= nil and self.screen == nil then
    local now747 = self.now or 0
    local due_items = nil
    for item_r, ent in pairs(self._grid_gray_retry747) do
      if ent ~= nil and now747 >= (ent.next_t or 0) then
        due_items = due_items or {}
        due_items[#due_items + 1] = { item_r, ent.index, ent.pos }
      end
    end
    if due_items ~= nil then
      for i = 1, #due_items do
        local d = due_items[i]
        pcall(self._grid_disable_gray_raycast, self, d[1], d[2], d[3])
      end
    end
  end`
);

patch(
  'P1-2_grid_disable_gray_raycast失败入队自动重试',
  `function Controller:_grid_disable_gray_raycast(item, index, pos)
  local cg = self:_grid_item_child_cached(item, index, pos, "gray")
  if cg == nil then return false end
  local rec = self:_grid_item_rec(item, index)
  if rec ~= nil and rec.gray_noray == true then return true end
  -- 746（P1-2）：逐属性独立受保护写入并读回确认，任一属性抛错或未落为 false 时不置完成，保留下一轮重试。
  local ok1, d1 = pcall(c746_disable_prop, cg, "raycastTarget")
  local ok2, d2 = pcall(c746_disable_prop, cg, "blockRaycast")
  local ok3, d3 = pcall(c746_disable_prop, cg, "interactable")
  local all_done = (ok1 and d1 == true) and (ok2 and d2 == true) and (ok3 and d3 == true)
  if rec ~= nil and all_done then rec.gray_noray = true end
  return all_done
end`,
  `function Controller:_grid_disable_gray_raycast(item, index, pos)
  local cg = self:_grid_item_child_cached(item, index, pos, "gray")
  if cg == nil then return false end
  local rec = self:_grid_item_rec(item, index)
  if rec ~= nil and rec.gray_noray == true then
    if self._grid_gray_retry747 ~= nil then
      self._grid_gray_retry747[item] = nil
      if next(self._grid_gray_retry747) == nil then self._grid_gray_retry747 = nil end
    end
    return true
  end
  -- 746+747（P1-2）：逐属性独立受保护写入并读回确认；失败项登记到 _grid_gray_retry747，由 tick 原地自动重试，不依赖玩家滚动或手动重刷。
  local ok1, d1 = pcall(c746_disable_prop, cg, "raycastTarget")
  local ok2, d2 = pcall(c746_disable_prop, cg, "blockRaycast")
  local ok3, d3 = pcall(c746_disable_prop, cg, "interactable")
  local all_done = (ok1 and d1 == true) and (ok2 and d2 == true) and (ok3 and d3 == true)
  if all_done then
    if rec ~= nil then rec.gray_noray = true end
    if self._grid_gray_retry747 ~= nil then
      self._grid_gray_retry747[item] = nil
      if next(self._grid_gray_retry747) == nil then self._grid_gray_retry747 = nil end
    end
  elseif item ~= nil then
    local q = self._grid_gray_retry747
    if q == nil then q = setmetatable({}, { __mode = "k" }); self._grid_gray_retry747 = q end
    local prev = q[item]
    local tries = (prev and prev.tries or 0) + 1
    local gap = (tries <= 2) and 0.25 or ((tries <= 5) and 0.5 or 1.0)
    q[item] = { index = index, pos = pos, tries = tries, next_t = (self.now or 0) + gap }
  end
  return all_done
end`
);

// ── 2. P1-1：同根替换按钮在切屏当帧与渲染/2s 保活中 O(1) 检测并自动换绑 ────────
patch(
  'P1-1_render_impl切屏标记与同根替换交互按钮即时换绑',
  `  do
    local lv_id = self.core and self.core.level and self.core.level.id
    if self._tree_screen ~= self.screen or self._tree_level ~= lv_id then`,
  `  local screen_switched747 = false
  do
    local lv_id = self.core and self.core.level and self.core.level.id
    if self._tree_screen ~= self.screen or self._tree_level ~= lv_id then
      screen_switched747 = true`
);

patch(
  'P1-1_render_impl对当前页交互按钮检查同根实例替换',
  `    if not self._created[n.id] then
      local ok_c, err_c = pcall(adapter.create_control, adapter, n)
      if not ok_c then`,
  `    if n.event ~= nil and adapter ~= nil and adapter.rebind_if_replaced747 ~= nil
       and (screen_switched747 or not self._created[n.id]) then
      local ok_rb, replaced = pcall(adapter.rebind_if_replaced747, adapter, n.id, n)
      if ok_rb and replaced == true then
        drop_props_of(n.id)
        self._created[n.id] = true
      end
    end
    if not self._created[n.id] then
      local ok_c, err_c = pcall(adapter.create_control, adapter, n)
      if not ok_c then`
);

// ── 3. P2-1：p745_set_vis_guard 返回写前可见状态，修复 cur_vis 未定义 Bug ─────
patch(
  'P2-1_p745_set_vis_guard返回写前可见状态',
  `local function p745_set_vis_guard(c, want)
  if want then
    if c.SetActive ~= nil and c.active ~= true then c:SetActive(true) end
  end
  if c.SetVisible ~= nil and c.visible ~= want then c:SetVisible(want) end
end`,
  `local function p745_set_vis_guard(c, want)
  local prev_vis = c.visible
  if want then
    if c.SetActive ~= nil and c.active ~= true then c:SetActive(true) end
  end
  if c.SetVisible ~= nil and prev_vis ~= want then c:SetVisible(want) end
  return prev_vis
end`
);

// ── 4. Perf-1：index_in 剪枝纯静态美术画片大容器 + invalidate_lookups 清理新状态 ──
patch(
  'Perf-1_invalidate_lookups清理747缓存并剪枝纯静态美术子树',
  `  self._subtree_dirty = true
  self._subtree_dirty_ids = nil
  self._hidden_enforced746 = nil
  self._baked_dirty = true
  path745_root_cache = {}
  self._lookup_gen = (self._lookup_gen or 0) + 1`,
  `  self._subtree_dirty = true
  self._subtree_dirty_ids = nil
  self._subtree_retry_at747 = nil
  self._subtree_urgent747 = false
  self._hidden_enforced746 = nil
  self._bound_nodes747 = nil
  self._baked_dirty = true
  path745_root_cache = {}
  self._lookup_gen = (self._lookup_gen or 0) + 1`
);

patch(
  'Perf-1_index_in剪枝纯静态画片叶子容器',
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
end`,
  `-- 747（Perf-1）：纯美术画片/撕边/静态背景大容器及其碎片均由 STATIC_PATH_655 O(1) 直查或专用组 GetChildren 访问，
-- 构建全树名称索引时登记容器本身但不钻入数千静态画片碎片，将 _build_name_index 节点数从 8,578 压降至 ~720。
local INDEX_PRUNE747 = {
  ["adapt715r.background"] = true,
  ["adapt715r.TR.23"] = true, ["adapt715r.TR.24"] = true,
  ["adapt715r.TL.25"] = true, ["adapt715r.BL.26"] = true,
  ["adapt715r.BR.27"] = true, ["adapt715r.BR.28"] = true,
  ["adapt715r.WAX.12"] = true,
  ["art641.game"] = true,
  ["art642.select.backdrop"] = true,
  ["select.thumb.pool"] = true,
  ["econ.ui742"] = true,
  ["art685.mark.overlay"] = true,
  ["police-v19"] = true,
}
local function should_prune_index747(cname, depth)
  if type(cname) ~= "string" then return false end
  if INDEX_PRUNE747[cname] then return true end
  if depth == 0 and cname:sub(1, 5) == "furn." then return true end
  if cname:sub(1, 3) == "td." and cname:find("%.page%.%d+$") ~= nil then return true end
  return false
end
local function index_in(ctrl, depth, idx, n)
  if ctrl == nil or depth > 16 then return n end
  n = n + 1
  local ok_n, cname = pcall(p744_name, ctrl)
  if ok_n and cname ~= nil then
    if idx[cname] == nil then idx[cname] = ctrl end
    if should_prune_index747(cname, depth) then return n end
  end
  local okc, children = pcall(p744_kids, ctrl)
  if okc and type(children) == "table" then
    for i = 1, #children do n = index_in(children[i], depth + 1, idx, n) end
  end
  return n
end`
);

// ── 4.5. Perf-1 配套：path_lookup_655 补齐 art685.mark.* O(1) 动态路由 ────────
patch(
  'Perf-1_path_lookup_655补齐art685_mark动态路由',
  `      elseif name:sub(1, 19) == "art647.select.card." and name:match("^art647%.select%.card%.%d+%.paper$") then
        route = "root/art641.select/art642.select.frames/grp653.static.1.art642.select.frames/" .. name
      else
        return nil
      end`,
  `      elseif name:sub(1, 19) == "art647.select.card." and name:match("^art647%.select%.card%.%d+%.paper$") then
        route = "root/art641.select/art642.select.frames/grp653.static.1.art642.select.frames/" .. name
      elseif name == "art685.mark.overlay" then
        route = "root/stage/art685.mark.overlay"
      elseif name:sub(1, 12) == "art685.mark." then
        local base_m = name:match("^(art685%.mark%.%d+%.%d+)%.stroke%.%d+$")
        if base_m ~= nil then
          route = "root/stage/art685.mark.overlay/" .. base_m .. "/" .. name
        elseif name:match("^art685%.mark%.%d+%.%d+$") then
          route = "root/stage/art685.mark.overlay/" .. name
        else
          return nil
        end
      else
        return nil
      end`
);

// ── 5. P1-1 & Wait 配套：Adapter 静态直查探活与同根替换自动换绑方法 ───────────
patch(
  'P1-1_Wait_Adapter增加has_static_route747与probe_static747与rebind_if_replaced747',
  `function Adapter:find(name)
  local hit0 = self.controls[name]`,
  `function Adapter:has_static_route747(name)
  if type(name) ~= "string" then return false end
  if STATIC_PATH_655[name] ~= nil then return true end
  local b = name:byte(1) or 0
  if b == 101 and name:sub(1, 5) == "econ." then return true end
  if b == 97 and (name == "art641.select" or name == "art642.select.frames" or name:sub(1, 19) == "art647.select.card.") then return true end
  if b == 103 and name == "grp653.static.1.art642.select.frames" then return true end
  if b == 115 and (name == "select.thumb.pool" or name:sub(1, 12) == "select.card.") then return true end
  return false
end
function Adapter:probe_static747(name)
  if game == nil or game.GetClientUIRoots == nil then return nil end
  local ok_r, roots = pcall(game.GetClientUIRoots)
  if not ok_r or not roots then return nil end
  local hit = path_lookup_655(roots, name)
  if hit ~= nil then return hit end
  local pm = self.cfg and self.cfg.path_map
  local p = pm and pm[name]
  if p ~= nil then return control_by_path(roots, p) end
  return nil
end
function Adapter:rebind_if_replaced747(id, node)
  if id == nil or not self:has_static_route747(id) then return false end
  local cur_ctrl = self.controls[id]
  local live = self:probe_static747(id)
  if live == nil or live == cur_ctrl then return false end
  -- 747（P1-1）：同根下旧控件被同名新实例替换！更新句柄、清子控件缓存、开射线并向新实例重绑全部输入事件。
  self.controls[id] = live
  self:_note_lookup_hit(id)
  if self._misses ~= nil then self._misses[id] = nil end
  if self._hidden_enforced746 ~= nil then self._hidden_enforced746[id] = nil end
  local pre = tostring(id) .. "."
  if self.subs ~= nil then
    for sk in pairs(self.subs) do
      if type(sk) == "string" and sk:sub(1, #pre) == pre then self.subs[sk] = nil end
    end
  end
  if self._sub_miss ~= nil then
    for sk in pairs(self._sub_miss) do
      if type(sk) == "string" and sk:sub(1, #pre) == pre then self._sub_miss[sk] = nil end
    end
  end
  if self.ensure_raycast ~= nil then pcall(self.ensure_raycast, self, live) end
  local bnode = node or (self._bound_nodes747 and self._bound_nodes747[id]) or (self.handlers and self.handlers[id])
  if bnode ~= nil and bnode.event ~= nil and (bnode.kind == "button" or bnode.kind == "cursor") then
    pcall(self.bind_input, self, id, bnode)
  end
  return true
end
function Adapter:find(name)
  local hit0 = self.controls[name]`
);

// ── 6. P1-3：enable_raycast 遇报错不提前收敛，下轮仅定向补扫失败子树 ──────────
patch(
  'P1-3_enable_raycast遇错记录失败节点并定向补扫后才收敛',
  `function Adapter:rearm_raycast(why)
  local st = self._ray
  if st == nil then return end
  if st.scans == 0 and not st.done then return end
  st.scans, st.idle, st.done = 0, 0, false
  if self.cfg and self.cfg.debug_raycast and print then
    print(PREFIX .. "射线开关：重新开始扫描（" .. tostring(why) .. "）")
  end
end`,
  `function Adapter:rearm_raycast(why)
  local st = self._ray
  if st == nil then return end
  if st.scans == 0 and not st.done and st.retry_nodes == nil then return end
  st.scans, st.idle, st.done, st.retry_nodes = 0, 0, false, nil
  if self.cfg and self.cfg.debug_raycast and print then
    print(PREFIX .. "射线开关：重新开始扫描（" .. tostring(why) .. "）")
  end
end`
);

patch(
  'P1-3_enable_raycast核心扫描错误追踪与失败子树定向补扫',
  `  local set, seen, samples = 0, 0, {}
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
  if seen > 0 and (st.idle >= RAY_IDLE_STOP or (st.scans == 1 and set > 0)) then
    st.done = true`,
  `  local set, seen, errs, samples = 0, 0, 0, {}
  local failed_nodes = nil
  local visited = {}
  local ray_want = self._ray_want
  local function walk(c, depth)
    if c == nil or depth > 20 or visited[c] then return end
    visited[c] = true
    -- 699+747（P1-3）：显式关闭的装饰层射线不能被重开；任一节点读写或取子节点失败均计入 errs 并登记失败子树，绝不带着报错提前收敛。
    local want = not (ray_want and ray_want[c] == false)
    local ok, before, did, kids = pcall(p745_ray_step, c, want)
    if not ok then
      local node_err = false
      local ok_b; ok_b, before = pcall(p744_ray_get, c)
      if not ok_b then before = nil; node_err = true end
      did = false
      if before ~= nil and before ~= want then
        did = pcall(p744_ray_set, c, want) == true
        if not did then node_err = true end
      end
      local ok_k; ok_k, kids = pcall(p744_kids, c)
      if not ok_k then kids = nil; node_err = true end
      if node_err then
        errs = errs + 1
        failed_nodes = failed_nodes or {}
        failed_nodes[#failed_nodes + 1] = c
      end
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
  local was_retry_pass = (type(st.retry_nodes) == "table" and #st.retry_nodes > 0)
  if was_retry_pass then
    for i = 1, #st.retry_nodes do walk(st.retry_nodes[i], 0) end
  else
    walk(root, 0)
  end
  st.scans = st.scans + 1
  if not was_retry_pass then st.seen = seen end
  st.set = set
  st.errs = errs
  if errs > 0 then
    st.retry_nodes = failed_nodes
    st.idle = 0
  else
    st.retry_nodes = nil
    local eff_seen = was_retry_pass and math.max(seen, st.seen or 0) or seen
    if eff_seen > 0 and set == 0 then st.idle = st.idle + 1 else st.idle = 0 end
    if eff_seen > 0 and (st.idle >= RAY_IDLE_STOP or (st.scans == 1 and set > 0) or was_retry_pass) then
      st.done = true`
);

patch(
  'P1-3_enable_raycast闭合else分支',
  `    if print and not st.announced then
      st.announced = true
      self:log("射线开关（raycastTarget）：已收敛，停止重扫（共扫 " .. tostring(st.scans)
        .. " 趟；本趟 " .. tostring(seen) .. " 个控件带该字段、需要打开 " .. tostring(set) .. " 个）")
    end
  elseif st.scans >= RAY_MAX_SCANS then`,
  `      if print and not st.announced then
        st.announced = true
        self:log("射线开关（raycastTarget）：已收敛，停止重扫（共扫 " .. tostring(st.scans)
          .. " 趟；本趟 " .. tostring(seen) .. " 个控件带该字段、需要打开 " .. tostring(set) .. " 个）")
      end
    end
  end
  if not st.done and st.scans >= RAY_MAX_SCANS then`
);

// ── 7. P2-1 + P1-4 配套：set_prop 接住写前可见性修复 cur_vis 并置紧急隐藏标志 ──
patch(
  'P2-1_edges写入同步失效已隐藏cell的子树完成标记',
  `  elseif key == "walls" then
    return self:_apply_edges(id, "wall", value)
  elseif key == "doors" then
    return self:_apply_edges(id, "door", value)`,
  `  elseif key == "walls" then
    if self._hidden_ids ~= nil and self._hidden_ids[id] and self._hidden_enforced746 ~= nil then
      self._hidden_enforced746[id] = nil
      self._subtree_dirty_ids = self._subtree_dirty_ids or {}
      self._subtree_dirty_ids[id] = true
      self._subtree_urgent747 = true
    end
    return self:_apply_edges(id, "wall", value)
  elseif key == "doors" then
    if self._hidden_ids ~= nil and self._hidden_ids[id] and self._hidden_enforced746 ~= nil then
      self._hidden_enforced746[id] = nil
      self._subtree_dirty_ids = self._subtree_dirty_ids or {}
      self._subtree_dirty_ids[id] = true
      self._subtree_urgent747 = true
    end
    return self:_apply_edges(id, "door", value)`
);

patch(
  'P2-1_P1-4_set_prop修复cur_vis并置即时隐藏标志',
  `    local vis = value and true or false
    pcall(p745_set_vis_guard, ctrl, vis)
    self._hidden_ids = self._hidden_ids or {}
    if vis then
      self._hidden_ids[id] = nil
      if self._subtree_dirty_ids ~= nil then self._subtree_dirty_ids[id] = nil end
      if self._hidden_enforced746 ~= nil then self._hidden_enforced746[id] = nil end
    else
      self._hidden_ids[id] = true
      if not (self._hidden_enforced746 ~= nil and self._hidden_enforced746[id] == true and cur_vis == false) then
        self._subtree_dirty_ids = self._subtree_dirty_ids or {}
        self._subtree_dirty_ids[id] = true
      end
    end`,
  `    local vis = value and true or false
    local ok_vg747, prev_vis747 = pcall(p745_set_vis_guard, ctrl, vis)
    self._hidden_ids = self._hidden_ids or {}
    if vis then
      self._hidden_ids[id] = nil
      if self._subtree_dirty_ids ~= nil then self._subtree_dirty_ids[id] = nil end
      if self._hidden_enforced746 ~= nil then self._hidden_enforced746[id] = nil end
      -- 若显示的是某隐藏容器下的命名子项（如 clues.grid 之于 clues），失效该父容器的已藏缓存确保子树重新收起。
      local pfx = type(id) == "string" and id:match("^([^%.]+)%.") or nil
      if pfx ~= nil and self._hidden_ids[pfx] then
        if self._hidden_enforced746 ~= nil then self._hidden_enforced746[pfx] = nil end
        self._subtree_dirty_ids = self._subtree_dirty_ids or {}
        self._subtree_dirty_ids[pfx] = true
        self._subtree_urgent747 = true
      end
    else
      self._hidden_ids[id] = true
      -- 747（P2-1）：用写前回读 prev_vis747 替代未定义 cur_vis，使已隐藏子树的幂等去重真正生效。
      if not (self._hidden_enforced746 ~= nil and self._hidden_enforced746[id] == true and ok_vg747 and prev_vis747 == false) then
        self._subtree_dirty_ids = self._subtree_dirty_ids or {}
        self._subtree_dirty_ids[id] = true
        self._subtree_urgent747 = true
      end
    end`
);

// ── 8. P1-1 配套：bind_input 为新实例自动开启射线并登记交互节点表 ─────────────
patch(
  'P1-1_bind_input新实例自动ensure_raycast',
  `  self._listeners = self._listeners or setmetatable({}, {__mode='k'})
  local done=self._listeners[ctrl] or {}; self._listeners[ctrl]=done`,
  `  self._listeners = self._listeners or setmetatable({}, {__mode='k'})
  local was_bound747 = (self._listeners[ctrl] ~= nil)
  local done=self._listeners[ctrl] or {}; self._listeners[ctrl]=done
  if not was_bound747 and self:has_static_route747(id) and self.ensure_raycast ~= nil and not (self._ray_want and self._ray_want[ctrl] == false) then
    pcall(self.ensure_raycast, self, ctrl)
  end`
);

patch(
  'P1-1_bind_input登记可点击交互节点表',
  `  self._retry_input=self._retry_input or {}
  if pending then self._retry_input[id]=node else self._retry_input[id]=nil end
end`,
  `  self._retry_input=self._retry_input or {}
  if pending then self._retry_input[id]=node else self._retry_input[id]=nil end
  if self:has_static_route747(id) then
    self._bound_nodes747 = self._bound_nodes747 or {}
    self._bound_nodes747[id] = node
  end
end`
);

// ── 9. P1-4：enforce_hidden_subtrees 遇临时错误重新入队并在 on_tick 节流重试 ──
patch(
  'P1-4_enforce_hidden_subtrees失败项重入队不丢待办',
  `function Adapter:enforce_hidden_subtrees()
  local full = self._subtree_dirty
  self._subtree_dirty = false
  local pending = self._subtree_dirty_ids
  self._subtree_dirty_ids = nil
  local hid = self._hidden_ids
  if hid == nil then return end
  local targets = full and hid or pending
  if targets == nil then return end
  if full then self._hidden_enforced746 = {} end
  local done_map = self._hidden_enforced746
  if done_map == nil then done_map = {}; self._hidden_enforced746 = done_map end
  local function hide_one746(node)
    local nm = node.name
    if nm ~= nil and nm ~= "" and DECOR[nm] == true then return false, nil end
    if node.visible ~= false then node:SetVisible(false) end
    return true, node:GetChildren()
  end
  local function hide_leaf746(node)
    local nm = node.name
    if nm ~= nil and nm ~= "" and DECOR[nm] == true then return end
    if node.visible ~= false then node:SetVisible(false) end
  end
  for id in pairs(targets) do
    if hid[id] then
      local c = self:find(id)
      if c ~= nil then
        local ok_k, kids = pcall(p744_kids, c)
        if ok_k and type(kids) == "table" then
          local all_ok = true
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil and k.SetVisible then
              local ok1, cont, kk = pcall(hide_one746, k)
              if not ok1 then
                all_ok = false
              elseif cont and type(kk) == "table" then
                for j = 1, math.min(#kk, 32) do
                  local k2 = kk[j]
                  if k2 ~= nil and k2.SetVisible then
                    if not pcall(hide_leaf746, k2) then all_ok = false end
                  end
                end
              end
            end
          end
          if all_ok then done_map[id] = true end
        end
      end
    end
  end
end`,
  `function Adapter:enforce_hidden_subtrees()
  local full = self._subtree_dirty
  self._subtree_dirty = false
  self._subtree_urgent747 = false
  local pending = self._subtree_dirty_ids
  self._subtree_dirty_ids = nil
  local hid = self._hidden_ids
  if hid == nil then self._subtree_retry_at747 = nil; return end
  local targets = full and hid or pending
  if targets == nil then self._subtree_retry_at747 = nil; return end
  if full then self._hidden_enforced746 = {} end
  local done_map = self._hidden_enforced746
  if done_map == nil then done_map = {}; self._hidden_enforced746 = done_map end
  local function hide_one746(node)
    local nm = node.name
    if nm ~= nil and nm ~= "" and DECOR[nm] == true then return false, nil end
    if node.visible ~= false then node:SetVisible(false) end
    return true, node:GetChildren()
  end
  local function hide_leaf746(node)
    local nm = node.name
    if nm ~= nil and nm ~= "" and DECOR[nm] == true then return end
    if node.visible ~= false then node:SetVisible(false) end
  end
  local retry_ids = nil
  for id in pairs(targets) do
    if hid[id] then
      local c = self:find(id)
      local ok_done = false
      if c ~= nil then
        local ok_k, kids = pcall(p744_kids, c)
        if ok_k and type(kids) == "table" then
          local all_ok = true
          for i = 1, math.min(#kids, 64) do
            local k = kids[i]
            if k ~= nil and k.SetVisible then
              local ok1, cont, kk = pcall(hide_one746, k)
              if not ok1 then
                all_ok = false
              elseif cont and type(kk) == "table" then
                for j = 1, math.min(#kk, 32) do
                  local k2 = kk[j]
                  if k2 ~= nil and k2.SetVisible then
                    if not pcall(hide_leaf746, k2) then all_ok = false end
                  end
                end
              end
            end
          end
          if all_ok then
            done_map[id] = true
            ok_done = true
          end
        end
      end
      -- 747（P1-4）：控件暂不可达、取子节点或隐藏任一子节点失败时，重新放回待办队列，0.25s 后自动重试，不丢旧页隐藏待办。
      if not ok_done then
        retry_ids = retry_ids or {}
        retry_ids[id] = true
      end
    end
  end
  if retry_ids ~= nil then
    self._subtree_dirty_ids = self._subtree_dirty_ids or {}
    for rid in pairs(retry_ids) do
      if hid[rid] then self._subtree_dirty_ids[rid] = true end
    end
    self._subtree_retry_at747 = (self.clock or 0) + 0.25
  else
    self._subtree_retry_at747 = nil
  end
end`
);

patch(
  'P1-4_on_tick按即时标志或0.25s节流调度enforce_hidden_subtrees',
  `  if self._subtree_dirty or (self._subtree_dirty_ids ~= nil and next(self._subtree_dirty_ids) ~= nil) then
    pcall(self.enforce_hidden_subtrees, self)
  end`,
  `  if self._subtree_dirty or (self._subtree_dirty_ids ~= nil and next(self._subtree_dirty_ids) ~= nil
     and (self._subtree_urgent747 or self._subtree_retry_at747 == nil or (self.clock or 0) >= self._subtree_retry_at747)) then
    pcall(self.enforce_hidden_subtrees, self)
  end`
);

// ── 10. Perf-2：murdoku_set_vis 关内稳态对 cell.* 走 O(1) stage/board 直查 ─────
patch(
  'Perf-2_murdoku_set_vis关内稳态cell直查免全树DFS',
  `  local c = ad.controls and ad.controls[nm] or nil
  if c == nil then
    -- 745：若已确认为同代缺失项，跳过每帧 pcall(ad.find) 开销。
    local misses = ad._misses
    if misses ~= nil then
      local stamp = misses[nm]
      if stamp == false or (type(stamp) == "number" and (ad.clock or 0) < stamp) then return 0 end
    end
    local ok_f, res_f = pcall(ad.find, ad, nm)
    if ok_f then c = res_f end
  end`,
  `  local c = ad.controls and ad.controls[nm] or nil
  if c == nil then
    -- 747（Perf-2）：稳态兜底（非 forcing）查找 cell.* 时仅 O(1) 检查 board/stage 直接子节点，避免每 1~2s 触发全树索引重建。
    if not forcing and type(nm) == "string" and nm:sub(1, 5) == "cell." then
      local host = (ad.controls and (ad.controls["board"] or ad.controls["stage"])) or nil
      if host ~= nil and host.GetChild ~= nil then
        local ok_g, child = pcall(host.GetChild, host, nm)
        if ok_g and child ~= nil then
          ad.controls[nm] = child
          c = child
        end
      end
      if c == nil then return 0 end
    else
      local misses = ad._misses
      if misses ~= nil then
        local stamp = misses[nm]
        if stamp == false or (type(stamp) == "number" and (ad.clock or 0) < stamp) then return 0 end
      end
      local ok_f, res_f = pcall(ad.find, ad, nm)
      if ok_f then c = res_f end
    end
  end`
);

// ── 11. Wait：商城/选关静态缺项每 2.0s O(1) 轻量探活，挂回等待 <= 2.0s ─────────
patch(
  'Wait_on_update对静态路径缺项每2秒O1探活压缩等待时长',
  `          else
            local stamp = miss_tbl and miss_tbl[id]
            if ad_r.controls[id] ~= nil then
              need_sec_render = true
              break
            elseif stamp == nil or (stamp ~= false and clk >= stamp) then
              local ok_p, found_p = pcall(ad_r.find, ad_r, id)
              if ok_p and found_p ~= nil then
                need_sec_render = true
                break
              end
            end
          end`,
  `          else
            local stamp = miss_tbl and miss_tbl[id]
            if ad_r.controls[id] ~= nil then
              need_sec_render = true
              break
            elseif ad_r.has_static_route747 ~= nil and ad_r:has_static_route747(id) then
              -- 747：静态路径控件（如 econ.shop736.*）用 O(1) path_lookup 每 2.0s 轻量探活（0 次 GetChildren、0 次 build_layout），
              -- 挂回后等待时间从 13.6s 压缩至 <= 2.0s。
              local ptab = current.controller._static_probe_at747
              if ptab == nil then ptab = {}; current.controller._static_probe_at747 = ptab end
              local next_at = ptab[id] or 0
              if clk >= next_at then
                ptab[id] = clk + 1.9
                local ok_s, found_s = pcall(ad_r.probe_static747, ad_r, id)
                if ok_s and found_s ~= nil then
                  ad_r.controls[id] = found_s
                  if miss_tbl ~= nil then miss_tbl[id] = nil end
                  if ad_r._miss_streak ~= nil then ad_r._miss_streak[id] = nil end
                  ptab[id] = nil
                  need_sec_render = true
                  break
                end
              end
            elseif stamp == nil or (stamp ~= false and clk >= stamp) then
              local ok_p, found_p = pcall(ad_r.find, ad_r, id)
              if ok_p and found_p ~= nil then
                need_sec_render = true
                break
              end
            end
          end`
);

// ── 12. P2-3：格子巡检“完整”定义补齐 box（content/middle/body/root）──────────
patch(
  'P2-3_格子巡检完整判定补齐box容器',
  `      -- 746（P1-1）：已齐全格子保持 120 帧稳态巡检零重枚举；
      -- 任一格子缺少 face 或 x 时，仅对该缺项格子按退避周期（前 2 次 30 帧，之后 60 帧，常驻 120 帧）重查，绝不封死晚挂控件恢复。`,
  `      -- 746+747（P1-1 & P2-3）：已齐全（box/face/x 三者均就绪）格子保持 120 帧稳态巡检零重枚举；
      -- 任一格子缺少 box、face 或 x 时，仅对该缺项格子按退避周期（前 2 次 30 帧，之后 60 帧，常驻 120 帧）重查，绝不封死晚挂控件恢复。`
);

patch(
  'P2-3_格子巡检rec_complete与got_all含box',
  `            local rec_complete = (rec ~= nil and rec.face ~= nil and rec.x ~= nil)
            if full_pass746 or not rec_complete then
              local cell = ad745 and ad745.controls and ad745.controls[cid] or nil
              if cell == nil and ad745 ~= nil then
                local ok_f, res_f = pcall(ad745.find, ad745, cid)
                if ok_f then cell = res_f end
              end
              if cell ~= nil then
                local need_scan = (rec == nil or rec.cell ~= cell)
                if not need_scan and not rec_complete then
                  local next_f = rec.next_probe746 or 0
                  if f745 >= next_f then need_scan = true end
                end
                if need_scan then
                  local probes = (rec ~= nil and rec.cell == cell) and ((rec.probe746 or 0) + 1) or 1
                  rec = { cell = cell, probe746 = probes }
                  pcall(scan_cell_kids746, cell, rec)
                  local got_all = (rec.face ~= nil and rec.x ~= nil)`,
  `            local rec_complete = (rec ~= nil and rec.box ~= nil and rec.face ~= nil and rec.x ~= nil)
            if full_pass746 or not rec_complete then
              local cell = ad745 and ad745.controls and ad745.controls[cid] or nil
              if cell == nil and ad745 ~= nil then
                -- 747（Perf-2 配套）：格子巡检优先 O(1) 查 board/stage 直接子节点，避免缺格反复触发全树索引重建。
                local host747 = ad745.controls and (ad745.controls["board"] or ad745.controls["stage"]) or nil
                if host747 ~= nil and host747.GetChild ~= nil then
                  local ok_c, ch_c = pcall(host747.GetChild, host747, cid)
                  if ok_c and ch_c ~= nil then
                    ad745.controls[cid] = ch_c
                    cell = ch_c
                  end
                end
                if cell == nil and fc745.stable == 0 then
                  local ok_f, res_f = pcall(ad745.find, ad745, cid)
                  if ok_f then cell = res_f end
                end
              end
              if cell ~= nil then
                local need_scan = (rec == nil or rec.cell ~= cell)
                if not need_scan and not rec_complete then
                  local next_f = rec.next_probe746 or 0
                  if f745 >= next_f then need_scan = true end
                end
                if need_scan then
                  local probes = (rec ~= nil and rec.cell == cell) and ((rec.probe746 or 0) + 1) or 1
                  rec = { cell = cell, probe746 = probes }
                  pcall(scan_cell_kids746, cell, rec)
                  local got_all = (rec.box ~= nil and rec.face ~= nil and rec.x ~= nil)`
);

// ── 13. P2-4：adapt14_pagers 返回逐项失败集合，失败仅定向重试不破整页稳态 ────
patch(
  'P2-4_adapt14_pagers支持仅重试失败翻页控件',
  `local function adapt14_pagers(find,transform,w)
  local all_ok = true
  for _,v in ipairs({{'left','adapt715r.LM.19','hit.select.prev',-1},{'right','adapt715r.RM.20','hit.select.next',1}}) do
    local art=find('art647.select.diamond.'..v[1])
    local hit=find(v[3])
    local x,y=adapt715r_pair(art,'GetAnchoredPosition')
    local hw,hh=adapt715r_pair(hit,'GetSizeDelta')
    if x and y and hw and hh and hw>0 and hh>0 then
      local center=v[4]*(w/2-12-hw/2)
      local ok1 = transform(v[2],center-x,0,1)
      local ok2 = transform(v[3],center,y,1)
      if not (ok1 and ok2) then all_ok = false end
    else
      all_ok = false
    end
  end
  return all_ok
end`,
  `local ADAPT14_PAGER_SPECS747 = {
  {'left','adapt715r.LM.19','hit.select.prev',-1,'lm','prev'},
  {'right','adapt715r.RM.20','hit.select.next',1,'rm','next'},
}
local function adapt14_pagers(find,transform,w,only_keys)
  local failed = nil
  for i=1,#ADAPT14_PAGER_SPECS747 do
    local v = ADAPT14_PAGER_SPECS747[i]
    local want1 = (only_keys == nil or only_keys[v[5]] == true)
    local want2 = (only_keys == nil or only_keys[v[6]] == true)
    if want1 or want2 then
      local art=find('art647.select.diamond.'..v[1])
      local hit=find(v[3])
      local x,y=adapt715r_pair(art,'GetAnchoredPosition')
      local hw,hh=adapt715r_pair(hit,'GetSizeDelta')
      if x and y and hw and hh and hw>0 and hh>0 then
        local center=v[4]*(w/2-12-hw/2)
        if want1 and not transform(v[2],center-x,0,1) then
          failed = failed or {}; failed[v[5]] = true
        end
        if want2 and not transform(v[3],center,y,1) then
          failed = failed or {}; failed[v[6]] = true
        end
      else
        failed = failed or {}
        if want1 then failed[v[5]] = true end
        if want2 then failed[v[6]] = true end
      end
    end
  end
  return failed == nil, failed
end`
);

patch(
  'P2-4_sync_adapt715r拆分主布局稳态与翻页失败项定向重试',
  `  if gen~=st.gen then st.handles={};st.gen=gen;st.leaves=nil;st.leafState=nil;st.tearKids={};st.tearState={};st.cardFont={};st.page=nil;st.steady_ok745=false;st.fill_col745=nil end`,
  `  if gen~=st.gen then st.handles={};st.gen=gen;st.leaves=nil;st.leafState=nil;st.tearKids={};st.tearState={};st.cardFont={};st.page=nil;st.steady_ok745=false;st.main_ok747=false;st.pager_retry747=nil;st.fill_col745=nil end`
);

patch(
  'P2-4_sync_adapt715r稳态分支仅重试失败翻页热区',
  `  -- 745：若页面/画布尺寸/设备槽/控件树代/确认条/选关页码均未变且上一趟已全部就绪，直接早退！
  if not force and not pageChanged and valid_sz and st.steady_ok745==true
     and st.steady_cw==cw and st.steady_ch==ch and st.steady_slot==slot
     and st.steady_pend==pend_act and st.steady_spage==spage then
    return
  end`,
  `  -- 747（P2-4）：若主布局已稳态且分辨率/页面/槽位/确认条/选关页码均未变：
  --   无失败翻页项 → 立即 0 开销早退；
  --   有失败翻页项 → 仅定向重试失败的 1~4 个翻页项，完全不重跑背景、卡片、撕边与目标表！
  if not force and not pageChanged and valid_sz and st.main_ok747==true
     and st.steady_cw==cw and st.steady_ch==ch and st.steady_slot==slot
     and st.steady_pend==pend_act and st.steady_spage==spage then
    if st.pager_retry747 == nil then
      return
    end
    local function transform_p747(name,x,y,s)
      local c=find(name)
      if not c then return false end
      local ok,matched=pcall(e745_transform,c,x,y,s,1e-5)
      return ok and matched
    end
    local p_ok, p_fail = adapt14_pagers(find, transform_p747, 1600, st.pager_retry747)
    st.pager_retry747 = p_fail
    st.steady_ok745 = (p_ok == true)
    return
  end`
);

patch(
  'P2-4_sync_adapt715r分别记录主布局与翻页重试表',
  `  local pagers_ok=adapt14_pagers(find,transform,w)`,
  `  local pagers_ok, pager_failed747 = adapt14_pagers(find,transform,w,nil)`
);

patch(
  'P2-4_sync_adapt715r写回main_ok747与pager_retry747',
  `  -- 746（P1-3 & P2-1）：翻页 4 控件定位、board 定位、全部撕边组预期叶数与显隐全部确认就绪才进入 steady 早退。
  st.steady_ok745=(visible==true and missing==0 and failed==0 and cardsOk==true and wax_ok==true and pagers_ok==true and board_ok==true and st.leafState==bgWanted and tears_done745)
  if st.steady_ok745 then
    st.steady_cw=phys_cw; st.steady_ch=phys_ch; st.steady_slot=slot
    st.steady_pend=pend_act; st.steady_spage=spage
  end`,
  `  -- 747（P2-4）：主布局（背景/卡片/撕边/WAX/board/目标表）与翻页 4 控件解耦记录；
  -- 主布局就绪时保存稳态基准，仅将未就绪的翻页项挂入 st.pager_retry747 单独重试。
  st.main_ok747=(visible==true and missing==0 and failed==0 and cardsOk==true and wax_ok==true and board_ok==true and st.leafState==bgWanted and tears_done745)
  st.pager_retry747=pager_failed747
  st.steady_ok745=(st.main_ok747 and pagers_ok==true)
  if st.main_ok747 then
    st.steady_cw=phys_cw; st.steady_ch=phys_ch; st.steady_slot=slot
    st.steady_pend=pend_act; st.steady_spage=spage
  end`
);

// ── 13.5. Perf-3：sync_adapt715r 背景 649 叶与撕边 591 叶整批 pcall + 异常降级 ──
patch(
  'Perf-3_背景649叶整批pcall与异常降级',
  `  if st.leaves and (st.leafState~=bgWanted or force) then
    local done=true
    for _,c in ipairs(st.leaves) do done=set_visible(c,bgWanted) and done end
    if done then st.leafState=bgWanted end
  end`,
  `  local function batch_set_vis747(list, want)
    local all_ok = true
    for i = 1, #list do
      if not e745_set_vis_pair(list[i], want) then all_ok = false end
    end
    return all_ok
  end
  if st.leaves and (st.leafState~=bgWanted or force) then
    local ok_b, done = pcall(batch_set_vis747, st.leaves, bgWanted)
    if not ok_b then
      done = true
      for i = 1, #st.leaves do done = set_visible(st.leaves[i], bgWanted) and done end
    end
    if done then st.leafState=bgWanted end
  end`
);

patch(
  'Perf-3_撕边591叶整批pcall与异常降级',
  `        if kids then
          for i=1,#kids do done=set_visible(kids[i],selecting) and done end
        else
          done=false
        end`,
  `        if kids then
          local ok_t, t_done = pcall(batch_set_vis747, kids, selecting)
          if not ok_t then
            t_done = true
            for i=1,#kids do t_done = set_visible(kids[i],selecting) and t_done end
          end
          done = t_done and done
        else
          done=false
        end`
);

// ── 14. P2-2：商城回读确认严格化（读接口暂缺绝不放行签名）───────────────────
patch(
  'P2-2_sync_econ742读接口缺失不放行缓存签名',
  `  -- 746（P2-2）：保持中心锚定，并在写入后回读缩放、位置与显隐/激活；
  -- 若引擎静默忽略任一写入，则不缓存 applied_sig，确保下个 0.25s 周期自动重试直至到位。
  local function apply_and_verify_econ746(grp, sc, act)
    if grp.SetLocalScale then grp:SetLocalScale(sc,sc,1) end
    if grp.SetAnchoredPosition then grp:SetAnchoredPosition(0,0) end
    if grp.SetVisible then grp:SetVisible(act) end
    if grp.SetActive then grp:SetActive(act) end
    local ok_all = true
    if grp.GetLocalScale then
      local sx, sy = e745_pair(grp, 'GetLocalScale')
      if not sx or not sy or math.abs(sx - sc) >= 0.002 or math.abs(sy - sc) >= 0.002 then ok_all = false end
    end
    if grp.GetAnchoredPosition then
      local px, py = e745_pair(grp, 'GetAnchoredPosition')
      if not px or not py or math.abs(px) >= 0.002 or math.abs(py) >= 0.002 then ok_all = false end
    end
    if grp.visible ~= nil and grp.visible ~= act then ok_all = false end
    if grp.active ~= nil and grp.active ~= act then ok_all = false end
    return ok_all
  end
  local ok_e, verified = pcall(apply_and_verify_econ746, group, scale, active)`,
  `  -- 747（P2-2）：保持中心锚定并严格回读验证；凡存在写接口就必须能回读确认到目标值，
  -- 若读接口暂缺或返回 nil 一律视作未确认、绝不缓存签名，待接口可用后自动回正。
  local function apply_and_verify_econ747(grp, sc, act)
    local ok_all = true
    if grp.SetLocalScale then
      grp:SetLocalScale(sc,sc,1)
      if not grp.GetLocalScale then
        ok_all = false
      else
        local sx, sy = e745_pair(grp, 'GetLocalScale')
        if not sx or not sy or math.abs(sx - sc) >= 0.002 or math.abs(sy - sc) >= 0.002 then ok_all = false end
      end
    end
    if grp.SetAnchoredPosition then
      grp:SetAnchoredPosition(0,0)
      if not grp.GetAnchoredPosition then
        ok_all = false
      else
        local px, py = e745_pair(grp, 'GetAnchoredPosition')
        if not px or not py or math.abs(px) >= 0.002 or math.abs(py) >= 0.002 then ok_all = false end
      end
    end
    if grp.SetVisible then
      grp:SetVisible(act)
      if grp.visible ~= act then ok_all = false end
    end
    if grp.SetActive then
      grp:SetActive(act)
      if grp.active ~= act then ok_all = false end
    end
    return ok_all
  end
  local ok_e, verified = pcall(apply_and_verify_econ747, group, scale, active)`
);

// ── 15. P1-1 配套：OnUpdate 2s 保活对当前页已绑交互控件 O(1) 抽检同根替换 ─────
patch(
  'P1-1_OnUpdate_2秒保活抽检当前页交互控件同根替换',
  `      for id,node in pairs(adapter._retry_input or {}) do
        if in_lv745 or (type(id) ~= "string") or id:sub(1, 5) ~= "cell." then
          adapter:bind_input(id,node)
        end
      end
    end`,
  `      for id,node in pairs(adapter._retry_input or {}) do
        if in_lv745 or (type(id) ~= "string") or id:sub(1, 5) ~= "cell." then
          adapter:bind_input(id,node)
        end
      end
      -- 747（P1-1）：每 2s 对当前未隐藏的已绑交互按钮做 O(1) 静态路径句柄抽检（0 次 GetChildren）；
      -- 玩家站着不动遇到同根换按钮也能在 <= 2s 内自动换绑并重下发属性。
      if adapter._bound_nodes747 ~= nil and adapter.rebind_if_replaced747 ~= nil then
        local hid747 = adapter._hidden_ids
        local ctrl747 = session and session.controller
        local any_rebound = false
        for bid, bnode in pairs(adapter._bound_nodes747) do
          if hid747 == nil or not hid747[bid] then
            local ok_rb, changed = pcall(adapter.rebind_if_replaced747, adapter, bid, bnode)
            if ok_rb and changed == true then
              any_rebound = true
              if ctrl747 ~= nil and ctrl747._props ~= nil then ctrl747._props[bid] = nil end
            end
          end
        end
        if any_rebound and ctrl747 ~= nil then ctrl747.dirty = true end
      end
    end`
);

// ── 16. 版本标记更新为 v747 ────────────────────────────────────────────────
patch(
  '版本标记1',
  `if print then print("[murdoku] ===== 构建标记 v746 / 评审加固与切屏消峰 =====") end`,
  `if print then print("[murdoku] ===== 构建标记 v747 / 交互闭环与尾部消峰 =====") end`
);

patch(
  '版本标记2',
  `print("[murdoku] ===== 构建标记 v746 / 评审加固与切屏消峰 =====")`,
  `print("[murdoku] ===== 构建标记 v747 / 交互闭环与尾部消峰 =====")`
);

// ── 语法检查 + luac 字节码全局变量门禁 + shop_cold_render 回归检查 ──────────
fs.mkdirSync(temp, { recursive: true });
const basePathTmp = path.join(temp, 'base746_ref.lua');
const candPath = path.join(temp, 'candidate747.lua');
fs.writeFileSync(basePathTmp, original, 'utf8');
fs.writeFileSync(candPath, lua, 'utf8');

const syn = spawnSync('lua', ['-e', `assert(loadfile(${JSON.stringify(candPath)})); print("SYNTAX PASS")`], { encoding: 'utf8' });
assert.equal(syn.status, 0, 'Lua 语法检查失败:\n' + syn.stderr);
process.stdout.write(syn.stdout);

function collectEnvGlobals(filePath) {
  const r = spawnSync('luac', ['-p', '-l', filePath], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  assert.equal(r.status, 0, 'luac 反汇编失败:\n' + r.stderr);
  const map = new Map();
  for (const ln of r.stdout.split(/\r?\n/)) {
    const m = ln.match(/\[(\d+)\]\s+GETTABUP\s+\d+\s+\d+\s+\d+\s+;\s+_ENV\s+"([^"]+)"/);
    if (m) {
      const name = m[2];
      if (!map.has(name)) map.set(name, []);
      map.get(name).push(Number(m[1]));
    }
  }
  return map;
}
const baseGlobals = collectEnvGlobals(basePathTmp);
const candGlobals = collectEnvGlobals(candPath);
assert(!candGlobals.has('cur_vis'), 'P2-1 门禁失败：candidate747 仍存在未定义全局变量 cur_vis');
const newGlobals = [];
for (const [k, lines] of candGlobals.entries()) {
  if (!baseGlobals.has(k)) newGlobals.push(`${k}@L${lines.slice(0, 3).join(',')}`);
}
assert.equal(newGlobals.length, 0, 'luac 字节码门禁失败：新增未声明全局变量 -> ' + newGlobals.join('; '));
console.log('GLOBAL AUDIT PASS (removed cur_vis, new_globals=0)');

function runCold(scriptText) {
  const r = spawnSync('lua', [path.join(repo, 'tests/shop_cold_render.lua')], { input: scriptText, encoding: 'utf8' });
  assert.equal(r.status, 0, 'shop_cold_render 失败:\n' + r.stderr);
  const m = r.stdout.match(/COLD=(\d+) WRITES=(\d+) COLD_FINDS=(\d+) FINDS=(\d+)/);
  assert(m, '未匹配到 COLD 输出: ' + r.stdout);
  return m.slice(1).map(Number);
}
const coldBefore = runCold(original);
const coldAfter = runCold(lua);
console.log('COLD 746', coldBefore, '747', coldAfter);
assert.equal(coldAfter[0], coldBefore[0], 'COLD 应与 746 一致');
assert(coldAfter[1] <= coldBefore[1], 'WRITES 不应高于 746');
assert.equal(coldAfter[2], coldBefore[2], 'COLD_FINDS 应与 746 一致');
assert(coldAfter[3] <= coldBefore[3], 'FINDS 不应高于 746');

const candSha = sha(Buffer.from(lua, 'utf8'));
if (isCandidate) {
  console.log('CANDIDATE OK', candPath, 'patches=', patches.length, 'sha256=', candSha);
  process.exit(0);
}

// ── 正式产出：强验收契约（逐项断言 schema / SHA / 阶段差分 / 全部专项 / 多轮基准）──
const validationArg = process.argv.find((a) => a.startsWith('--validation='));
const validationPath = validationArg
  ? path.resolve(validationArg.slice(13))
  : path.join(temp, 'validation747.json');
assert(fs.existsSync(validationPath), '缺少独立验证结果文件：' + validationPath);
const validationFile = JSON.parse(fs.readFileSync(validationPath, 'utf8'));
const validation = validationFile.validation || validationFile;
assert.equal(validation.schema, '747-full-v1', '独立验证 schema 不符');
assert.equal(validation.candidateSha256, candSha, '独立验证对象 SHA256 与当前候选不一致');
assert.equal(validation.pass, true, '独立验证总标志 pass 必须为 true');
assert.equal(validation.equivalence?.stages, 32, '全量状态等价阶段数必须为 32');
assert.equal(validation.equivalence?.nodesPerStage, 8578, '每阶段节点数必须为 8578');
assert.equal(validation.equivalence?.controlSnapshotDiffs, 0, '全量控件快照差异必须为 0');
const requiredChecks = [
  // 原 5 项解禁专项
  'zone1_hex_back_confirm', 'zone2_pcall_guard', 'zone3_root_rebuild_fallback', 'zone4_face_and_x70', 'late_recovery',
  // 原 6 项 1056f21 评审闭环
  'r1_p1_1_late_x', 'r1_p1_2_gray_retry', 'r1_p1_3_pager_retry', 'r1_p2_1_tears_partial', 'r1_p2_2_econ_silent_ignore', 'r1_p2_3_missing_backoff',
  // 新增 9 项 955ebd00434d 评审闭环（4 P1 + 4 P2 + 商城等待时长压缩）
  'r2_p1_1_same_root_button_swap_switch', 'r2_p1_1_same_root_button_swap_idle',
  'r2_p1_2_gray_retry_idle_no_scroll',
  'r2_p1_3_raycast_partial_err_recovery',
  'r2_p1_4_hidden_subtree_err_requeue',
  'r2_p2_1_cur_vis_dedup_active',
  'r2_p2_2_econ_missing_getter_no_lock',
  'r2_p2_3_late_box_recovery',
  'r2_p2_4_pager_fail_isolated_retry',
  'r2_wait_shop_missing_fast_recover',
];
for (const key of requiredChecks) {
  assert.equal(validation.checks?.[key]?.pass, true, `强验收契约失败：缺少或未通过专项 [${key}]`);
}
assert(validation.benchmarks?.runs >= 5, '强验收契约失败：性能基准重复采样轮数必须 >= 5');
for (const sc of ['cold_boot', 'steady_home', 'steady_select', 'steady_level', 'steady_shop', 'screen_switch_burst', 'nav_flow']) {
  for (const ver of ['v743', 'v744', 'v745', 'v746', 'v747']) {
    assert(validation.benchmarks?.scenarios?.[sc]?.[ver]?.msMean !== undefined, `强验收契约失败：缺少基准 ${sc}.${ver}`);
  }
}

leaf.field.payload = Buffer.from(lua, 'utf8');
leaf.field.len = leaf.field.payload.length;
leaf.field.sub = null;

fs.mkdirSync(path.dirname(out), { recursive: true });
const recordBytes = new Map(g.recs.map((r) => [r.id, encodeMsg([r.field])]));
const report = writeGil(g, out, {
  label: '747 交互闭环与尾部消峰',
  expectDiffs: 1,
  expectMarker: 'v747',
  expectRecs: g.recs.length,
  assert(saved) {
    assert(findScriptLeaf(saved).buf.equals(Buffer.from(lua, 'utf8')), '重读脚本字节不一致');
    assert(saved.trailer.equals(g.trailer), 'trailer 不一致');
    for (const r of saved.recs) {
      assert(encodeMsg([r.field]).equals(recordBytes.get(r.id)), '控件记录被意外改动：' + r.name);
    }
    return true;
  },
});

const outDir = path.dirname(out);
const outStem = path.basename(out, path.extname(out));
const sidePrefix = outStem === '747_交互闭环与尾部消峰' ? '747' : outStem;
fs.writeFileSync(path.join(outDir, `${sidePrefix}_内嵌脚本.lua`), lua, 'utf8');
const summary = {
  baseVersion: '746',
  baseSha256: sha(g.src),
  baseBytes: g.src.length,
  scriptBytesBefore: Buffer.byteLength(original, 'utf8'),
  scriptBytesAfter: Buffer.byteLength(lua, 'utf8'),
  candidateSha256: candSha,
  globalAudit: { removedCurVis: true, newUndefinedGlobals: 0 },
  patches,
  cold: { before: coldBefore, after: coldAfter },
  records: g.recs.length,
  outputBytes: report.bytes,
  outputSha256: sha(report.g2.src),
  controlRecordsChanged: 0,
  fieldDifferences: report.diffs,
  validation,
  limits: [
    '性能、故障注入恢复与状态差分均基于导出自真实 .gil 的 8,578 节点控件树离线高仿真环境，尚未导入千星奇域真机实测',
    '同一套桩与同一口径下连续 5 轮重复采样统一横向对比 743 / 744 / 745 / 746 / 747，同时汇报均值、中位数、标准差与逐帧 P50/P95/P99/Max',
    '暂停自动 GC 的累计堆分配（allocKB）反映脚本层分配压力，不等价于真机常驻 RSS，真机仍需实测绝对帧时与 GPU 耗时',
    '747 以 tools/build_747.mjs 与 747_内嵌脚本.lua 为派生链，0 控件记录改动；writeGil 已升级为原子临时文件校验通过后 rename 落盘',
  ],
};
fs.writeFileSync(path.join(outDir, `${sidePrefix}_性能与验证.json`), JSON.stringify(summary, null, 2), 'utf8');
console.log('OUTPUT', out, report.bytes, sha(report.g2.src));
