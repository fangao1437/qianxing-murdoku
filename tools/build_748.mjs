// 748：从 747_交互闭环与尾部消峰.gil 派生，仅修改内嵌 Lua，不覆盖任何基准或旧存档。
// 全面回应提交 025cf62b9b9e《742 v12 至 747 功能破坏核验与优化方法不足独立审查报告》的
// 全部 10 项功能破坏（B1–B10）与 12 项方法不足（U1–U12），以零额外稳态负载原则完成修复并建立端到端自闭环构建门禁：
//   B1  ：enable_raycast 恢复 RAY_IDLE_STOP=3 且取消 scans==1/was_retry_pass 早停；首趟全树扫描后，后续确认趟跳过纯美术只读画片叶容器，既100%覆盖晚挂业务控件又不增加稳态负载；
//   B2  ：set_property("raycast") 拆分为单属性无闭包独立 pcall + 失败返回 false，彻底恢复异常隔离且不锁死 _props 缓存；
//   B3  ：横向清查并统一拆解 p745_set_vis_guard / e745_help_vis / t745_set_vis / e745_set_k_block640 为单操作无闭包独立 pcall + 失败不落盘缓存；
//   B4  ：sync_block640 确认条在 pending 打开期恢复每帧 cached 句柄置顶（关闭期 0 开销），遮罩全属性/置顶全成功才落盘 last_want745，失败下帧即重试；
//   B5/U7：在 Adapter 上建立统一交互控件看护管理器（_watch_handles748），把 Adapter:bind_input、util:_bind（help617/hint635/tutorial/block640）与动态 cell.* 全部纳入 O(1) 切屏+2s 保活自动换绑；
//   B6  ：sync_adapt715r 选关稳态提取极轻量 sync_card_fonts748（缓存 12 个文本框句柄，仅做 .text 引用比对，非选关页 0 开销），异步改字 0.25s 内自动重算字号；
//   B7/U8：修正 INDEX_PRUNE 拼写（TL.25→TR.25、BL.26→BR.26），补齐 grp653.static.1.art641.game/art642.select.backdrop 静态路由，并增加剪枝容器命名空间定向补查与构建期 .gil 树自动一致校验；
//   B8  ：murdoku_set_vis 在 forcing=true（切屏 60 帧窗口）恢复无视回读强写 SetVisible，稳态保持零无效写，且 cell.* 自动解析 stage 主容器防漏管；
//   B9  ：enable_cursor 与教程 M:_ensure_furniture 取消永久放弃，改 O(1) 静默退避探活，晚挂容器/board 挂回即自动完成；
//   B10/U12：消除模块级 path745_root_cache，迁入 Adapter 实例 _root_cache748，采用 roots[idx]==ctrl O(1) 在树验证并支持同名多根回退；
//   U2/U4/U11/U12：动态从 .gil 推导撕边/背景/标记层叶数（消除硬编码魔数），升级四维静态门禁（GETTABUP+SETTABUP+.gil 真实树核验+零模块级脏缓存），并由 build_748.mjs 直接调用入库的 tests/export_gil_tree.mjs 与 tests/perf_verify_748.lua 完成端到端自闭环验证后原子落盘。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { loadTree, findScriptLeaf, writeGil } from './gil/gilwrite.mjs';
import { encodeMsg } from './gil/gilread.mjs';

const repo = fileURLToPath(new URL('../', import.meta.url));
const runTmp = fs.mkdtempSync(path.join(os.tmpdir(), 'murdoku-748-'));
const keepTmp = process.argv.includes('--keep-tmp');
const isCandidate = process.argv.includes('--candidate');
const skipBench = process.argv.includes('--skip-bench');
const candOutArg = process.argv.find((a) => a.startsWith('--candidate-out='));
const out = path.resolve(process.argv[2] && !process.argv[2].startsWith('--')
  ? process.argv[2]
  : path.join(repo, '748_全核查修复与自闭环验证/748_全核查修复与自闭环验证.gil'));
const base = path.join(repo, '747_交互闭环与尾部消峰/747_交互闭环与尾部消峰.gil');
const base742 = path.join(repo, '742_调查背包美术还原/742_调查背包美术还原_v12.gil');

if (!isCandidate) assert(!fs.existsSync(out), '输出已存在，拒绝覆盖：' + out);

const sha = (b) => createHash('sha256').update(b).digest('hex');
const g = loadTree(base);
const leaf = findScriptLeaf(g);
const original = leaf.buf.toString('utf8');
assert.equal(sha(g.src), 'e979ed1ce89326f49bde6c5108b48164d2eb2ef840a2ec787541d98ed5acf377', '基准 747 SHA256 不匹配');

// ── U11：从真实 .gil 树自动推导关键容器叶数与节点存在性（消除手写魔数） ───────
const byId = new Map();
for (const r of g.recs) byId.set(r.id, { id: r.id, name: r.name || '', parent: r.parentId ?? null, kids: [] });
const gilRoots = [];
for (const n of byId.values()) {
  if (n.parent != null && byId.has(n.parent)) byId.get(n.parent).kids.push(n);
  else gilRoots.push(n);
}
const nodesByName = new Map();
for (const n of byId.values()) {
  if (!n.name) continue;
  let arr = nodesByName.get(n.name);
  if (!arr) { arr = []; nodesByName.set(n.name, arr); }
  arr.push(n);
}
function singleGroupKidCount(name) {
  const arr = nodesByName.get(name) || [];
  assert.equal(arr.length, 1, `.gil 中容器名必须唯一存在: ${name} (found=${arr.length})`);
  assert(arr[0].kids.length > 0, `.gil 中容器子节点数不应为 0: ${name}`);
  return arr[0].kids.length;
}
const bgLeafCount = singleGroupKidCount('adapt715r.background');
const tearDefs = [
  { name: 'adapt715r.TR.23', side: 'tr' },
  { name: 'adapt715r.TR.24', side: 'tr' },
  { name: 'adapt715r.TR.25', side: 'tr' },
  { name: 'adapt715r.BR.26', side: 'bl' },
  { name: 'adapt715r.BR.27', side: 'bl' },
  { name: 'adapt715r.BR.28', side: 'bl' },
].map((t) => ({ ...t, expect: singleGroupKidCount(t.name) }));
let markCtrlCount = 0;
{
  const ov = nodesByName.get('art685.mark.overlay');
  assert.equal(ov && ov.length, 1, '.gil 中 art685.mark.overlay 必须存在');
  (function walk(x) {
    for (const k of x.kids) {
      if (/^art685\.mark\.\d+\.\d+(\.stroke\.\d+)?$/.test(k.name)) markCtrlCount++;
      walk(k);
    }
  })(ov[0]);
  assert(markCtrlCount > 0, '.gil 中 art685.mark.* 数量应 > 0');
}
const derivedCounts = {
  bgLeaves: bgLeafCount,
  tears: Object.fromEntries(tearDefs.map((t) => [t.name, t.expect])),
  markCtrls: markCtrlCount,
};

let lua = original;
const patches = [];
function patch(tag, before, after) {
  const parts = lua.split(before);
  assert.equal(parts.length, 2, `补丁不唯一或未命中 [${tag}] (matches=${parts.length - 1})`);
  lua = lua.replace(before, () => after);
  patches.push(tag);
}

// ── 1. B2 / B3 / B10 / U6 / U12：单操作无闭包静态 helper + 实例级 root 缓存 ──
patch(
  'B2_B3_B10_单属性隔离helper与实例级root缓存',
  `local function p745_set_vis_guard(c, want)
  local prev_vis = c.visible
  if want then
    if c.SetActive ~= nil and c.active ~= true then c:SetActive(true) end
  end
  if c.SetVisible ~= nil and prev_vis ~= want then c:SetVisible(want) end
  return prev_vis
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
local path745_root_cache = {}`,
  `-- 748（B2/B3/U6）：全脚本统一使用单操作顶层无闭包静态 helper，同时保证 0 闭包分配与严格单属性异常隔离。
local function p748_set_active_true(c)
  if c.SetActive ~= nil and c.active ~= true then c:SetActive(true) end
end
local function p748_set_vis_if(c, want)
  local prev_vis = c.visible
  if c.SetVisible ~= nil and prev_vis ~= want then c:SetVisible(want) end
  return prev_vis
end
local function p745_set_vis_guard(c, want)
  if want then pcall(p748_set_active_true, c) end
  local ok_v, prev_vis = pcall(p748_set_vis_if, c, want)
  return ok_v, prev_vis
end
local function p748_set_bool_prop(c, key, want)
  local cur = c[key]
  if cur ~= nil and cur ~= want then c[key] = want end
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
local function p748_ray_leaf_step(c, want)
  local before = c.raycastTarget
  local did = false
  if before ~= nil and before ~= want then
    c.raycastTarget = want
    did = true
  end
  return before, did
end`
);

// ── 2. B5 / B10 / U12：invalidate_lookups 清理实例级 _root_cache748 与 _watch_handles748 ──
patch(
  'B5_B10_invalidate_lookups清理实例缓存',
  `  self._hidden_enforced746 = nil
  self._bound_nodes747 = nil
  self._baked_dirty = true
  path745_root_cache = {}
  self._lookup_gen = (self._lookup_gen or 0) + 1`,
  `  self._hidden_enforced746 = nil
  self._bound_nodes747 = nil
  self._watch_handles748 = nil
  self._name_idx_pruned748 = nil
  self._root_cache748 = nil
  self._baked_dirty = true
  self._lookup_gen = (self._lookup_gen or 0) + 1`
);

// ── 3. B7 / U8：修正 INDEX_PRUNE 拼写（TR.25 / BR.26）并记录被剪容器以支持零开销定向补查 ──
patch(
  'B7_U8_修正INDEX_PRUNE拼写并记录被剪枝容器',
  `local INDEX_PRUNE747 = {
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
end`,
  `-- 748（B7/U8）：修正 747 的 TL.25/BL.26 拼写错误为真实控件名 TR.25/BR.26（构建期已与 .gil 树自动断言一致）；
-- 同时将跳过展开的容器记入 pruned 表，供命名空间定向补查使用，保证被剪枝容器内动态子控件绝不失明。
local INDEX_PRUNE748 = {
  ["adapt715r.background"] = true,
  ["adapt715r.TR.23"] = true, ["adapt715r.TR.24"] = true,
  ["adapt715r.TR.25"] = true, ["adapt715r.BR.26"] = true,
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
  if INDEX_PRUNE748[cname] then return true end
  if depth == 0 and cname:sub(1, 5) == "furn." then return true end
  if cname:sub(1, 3) == "td." and cname:find("%.page%.%d+$") ~= nil then return true end
  return false
end
local function index_in(ctrl, depth, idx, n, pruned)
  if ctrl == nil or depth > 16 then return n end
  n = n + 1
  local ok_n, cname = pcall(p744_name, ctrl)
  if ok_n and cname ~= nil then
    if idx[cname] == nil then idx[cname] = ctrl end
    if should_prune_index747(cname, depth) then
      if pruned ~= nil and pruned[cname] == nil then pruned[cname] = ctrl end
      return n
    end
  end
  local okc, children = pcall(p744_kids, ctrl)
  if okc and type(children) == "table" then
    for i = 1, #children do n = index_in(children[i], depth + 1, idx, n, pruned) end
  end
  return n
end`
);

// ── 4. B7 / B10：补齐 STATIC_PATH_655 漏项 + path_lookup_655 O(1) 在树验证 + 实例缓存 ──
patch(
  'B7_B10_path_lookup_655补齐grp653并在树验证与实例缓存',
  `local function path_lookup_655(roots, name)
  local route = STATIC_PATH_655[name]
  if type(route) == "string" then
    route = route == "" and name or (route .. "/" .. name)
  end
  if route == nil then
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
  local function walk_route745(start, r, want)
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
end`,
  `local function walk_route748(start, r, want)
  local cur = start
  for k = 2, #r do
    cur = cur:GetChild(r[k])
    if cur == nil then return nil end
  end
  if cur ~= nil and cur.name == want then return cur end
  return nil
end
local function path_lookup_655(roots, name, root_cache)
  local route = STATIC_PATH_655[name]
  if type(route) == "string" then
    route = route == "" and name or (route .. "/" .. name)
  end
  if route == nil then
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
      end
    elseif b == 103 then
      if name == "grp653.static.1.art642.select.frames" then
        route = "root/art641.select/art642.select.frames/grp653.static.1.art642.select.frames"
      elseif name == "grp653.static.1.art641.game" then
        route = "root/art641.game/grp653.static.1.art641.game"
      elseif name == "grp653.static.1.art642.select.backdrop" then
        route = "root/art641.select/art642.select.backdrop/grp653.static.1.art642.select.backdrop"
      else
        return nil
      end
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
  -- 748（B10/U12）：根缓存挂在 Adapter 实例（不再用模块级共享表），通过 roots[idx] == ctrl 做 O(1) 在树验证；
  -- 即使旧根句柄尚未销毁仍可读 name，只要已被替换离树立刻淘汰重查；若存在同名多根且首根未命中则继续查其余同名根。
  local r0_name = route[1]
  local ent = root_cache ~= nil and root_cache[r0_name] or nil
  if ent ~= nil and roots[ent.idx] == ent.ctrl then
    local ok_c, hit_c = pcall(walk_route748, ent.ctrl, route, name)
    if ok_c and hit_c ~= nil then return hit_c end
    if not ent.multi then
      return nil
    end
  elseif ent ~= nil and root_cache ~= nil then
    root_cache[r0_name] = nil
  end
  local first_hit_root, first_hit_idx, match_count = nil, nil, 0
  local found_ctrl = nil
  for i = 1, #roots do
    local cur = roots[i]
    local ok, rn = pcall(p744_name, cur)
    if ok and rn == r0_name then
      match_count = match_count + 1
      if first_hit_root == nil then first_hit_root, first_hit_idx = cur, i end
      if found_ctrl == nil then
        local ok_w, hit = pcall(walk_route748, cur, route, name)
        if ok_w and hit ~= nil then
          found_ctrl = hit
          if root_cache ~= nil then
            root_cache[r0_name] = { ctrl = cur, idx = i, multi = (match_count > 1) }
          end
        end
      end
    end
  end
  if root_cache ~= nil and first_hit_root ~= nil then
    local prev = root_cache[r0_name]
    if prev == nil then
      root_cache[r0_name] = { ctrl = first_hit_root, idx = first_hit_idx, multi = (match_count > 1) }
    elseif match_count > 1 then
      prev.multi = true
    end
  end
  return found_ctrl
end`
);

// ── 5. B7：_build_name_index 记录被剪容器 + _index_lookup 对已知剪枝命名空间定向补查 ──
patch(
  'B7_build_name_index记录被剪枝容器并支持定向补查',
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
end`,
  `function Adapter:_build_name_index(roots)
  local prev_gen = self._name_idx_gen
  local prev_n = self._name_idx_nodes
  local idx = {}
  local pruned = {}
  local n = 0
  for i = 1, #roots do n = index_in(roots[i], 0, idx, n, pruned) end
  self._name_idx = idx
  self._name_idx_pruned748 = pruned
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
-- 748（B7/U8）：当按名查找命中已知剪枝容器命名空间且未在静态路由/主索引命中时，仅定向下钻对应 1 个被剪容器；
-- 常规缺失名（如 cell.* / fart.* / board）完全不触发，兼顾全剪枝性能与剪枝容器动态子控件可达性。
function Adapter:_pruned_container_for748(name)
  if type(name) ~= "string" then return nil end
  local pruned = self._name_idx_pruned748
  if pruned == nil then return nil end
  local b = name:byte(1) or 0
  if b == 101 and name:sub(1, 5) == "econ." then
    -- econ.shop736.* / econ.bag741.* 已由 path_lookup_655 做过 O(1) econ.ui742:GetChild 直查，缺失时不再重复枚举 econ.ui742
    if name:sub(1, 13) == "econ.shop736." or name:sub(1, 12) == "econ.bag741." then return nil end
    return pruned["econ.ui742"]
  end
  if b == 103 and name:sub(1, 16) == "grp653.static.1." then
    local tail = name:sub(17)
    return pruned[tail]
  end
  if b == 97 then
    if name:sub(1, 12) == "art641.game." then return pruned["art641.game"] end
    if name:sub(1, 23) == "art642.select.backdrop." then return pruned["art642.select.backdrop"] end
    if name:sub(1, 12) == "art685.mark." then return pruned["art685.mark.overlay"] end
    if name:sub(1, 10) == "adapt715r." then
      if name:sub(1, 21) == "adapt715r.background." then return pruned["adapt715r.background"] end
      return pruned["art641.game"]
    end
    if name:sub(1, 11) == "art675.wax." then return pruned["adapt715r.WAX.12"] end
    if name:sub(1, 19) == "art651.select.tear." then
      local side = name:sub(20, 21)
      if side == "tr" then return pruned["adapt715r.TR.23"], pruned["adapt715r.TR.24"], pruned["adapt715r.TR.25"] end
      if side == "bl" then return pruned["adapt715r.BR.26"], pruned["adapt715r.BR.27"], pruned["adapt715r.BR.28"] end
    end
    if name:sub(1, 14) == "art647.select." then return pruned["art642.select.backdrop"] end
  elseif b == 116 and name:sub(1, 3) == "td." then
    local page_box = name:match("^(td%.[^%.]+%.page%.%d+)%.")
    if page_box ~= nil then return pruned[page_box] end
  elseif b == 115 and name:sub(1, 12) == "select.card." then
    return pruned["select.thumb.pool"]
  end
  return nil
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
    hit = idx[name]
    if hit ~= nil then return hit end
  end
  -- 748（B7）：仅当 name 属于已知被剪容器命名空间时，做单容器定向查找（0 全树成本）。
  local c1, c2, c3 = self:_pruned_container_for748(name)
  if c1 ~= nil then
    local found = find_in(c1, name, 0)
    if found == nil and c2 ~= nil then found = find_in(c2, name, 0) end
    if found == nil and c3 ~= nil then found = find_in(c3, name, 0) end
    if found ~= nil then
      idx[name] = found
      return found
    end
  end
  return nil
end`
);

// ── 6. B5 / U7 / B10：统一交互控件看护管理器（取代碎片化 _bound_nodes747，覆盖 Adapter:bind_input + util:_bind + 动态 cell.*）──
patch(
  'B5_U7_统一交互控件看护管理器与实例root缓存调用',
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
  local hit0 = self.controls[name]
  if hit0 ~= nil then return hit0 end
  local miss = self._misses
  if miss ~= nil then
    local stamp = miss[name]
    if stamp ~= nil then
      if stamp == false or self.clock < stamp then return nil end
    end
  end
  if game == nil or game.GetClientUIRoots == nil then return nil end
  local roots = game.GetClientUIRoots()
  if roots then
    if self.cfg == nil or self.cfg.find_index ~= false then
      local hit = path_lookup_655(roots, name)`,
  `function Adapter:has_static_route747(name)
  if type(name) ~= "string" then return false end
  if STATIC_PATH_655[name] ~= nil then return true end
  local b = name:byte(1) or 0
  if b == 101 and name:sub(1, 5) == "econ." then return true end
  if b == 97 and (name == "art641.select" or name == "art642.select.frames" or name == "art685.mark.overlay"
      or name:sub(1, 19) == "art647.select.card." or name:sub(1, 12) == "art685.mark.") then return true end
  if b == 103 and (name == "grp653.static.1.art642.select.frames"
      or name == "grp653.static.1.art641.game"
      or name == "grp653.static.1.art642.select.backdrop") then return true end
  if b == 115 and (name == "select.thumb.pool" or name:sub(1, 12) == "select.card.") then return true end
  return false
end
function Adapter:probe_static747(name, roots_opt)
  local roots = roots_opt
  if roots == nil then
    if game == nil or game.GetClientUIRoots == nil then return nil end
    local ok_r; ok_r, roots = pcall(game.GetClientUIRoots)
    if not ok_r or not roots then return nil end
  end
  local rc = self._root_cache748
  if rc == nil then rc = {}; self._root_cache748 = rc end
  local hit = path_lookup_655(roots, name, rc)
  if hit ~= nil then return hit end
  local pm = self.cfg and self.cfg.path_map
  local p = pm and pm[name]
  if p ~= nil then return control_by_path(roots, p) end
  return nil
end
-- 748（B5/U7）：统一交互控件句柄看护管理器，同时覆盖 Adapter:bind_input 静态按钮、util:_bind（help617/hint635/tutorial/block640）
-- 与动态棋盘格 cell.*，全部走 O(1) 路径或直属父容器 GetChild 比对（0 次 GetChildren）。
function Adapter:register_watch_handle748(id, ctrl, kind, payload, owner, sync_tbl)
  if id == nil or ctrl == nil then return end
  local w = self._watch_handles748
  if w == nil then w = {}; self._watch_handles748 = w end
  w[id] = { id = id, ctrl = ctrl, kind = kind, payload = payload, owner = owner, sync_tbl = sync_tbl }
end
function Adapter:probe_live_handle748(id, roots_opt)
  if type(id) ~= "string" then return nil end
  if self:has_static_route747(id) then
    return self:probe_static747(id, roots_opt)
  end
  if id:sub(1, 5) == "cell." then
    local host = (self.controls and (self.controls["board"] or self.controls["stage"])) or self:probe_static747("stage", roots_opt)
    if host ~= nil and host.GetChild ~= nil then
      local ok_g, child = pcall(p744_child, host, id)
      if ok_g and child ~= nil then return child end
    end
    return nil
  end
  if id:sub(1, 3) == "td." then
    local rname = id:match("^(td%.[^%.]+)%.")
    if rname ~= nil then
      local host = (self.controls and self.controls[rname]) or self:probe_static747(rname, roots_opt)
      if host ~= nil and host.GetChild ~= nil then
        local ok_g, child = pcall(p744_child, host, id)
        if ok_g and child ~= nil then return child end
      end
    end
  end
  return nil
end
function Adapter:_swap_live_handle748(id, live)
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
  if self.ensure_raycast ~= nil and not (self._ray_want and self._ray_want[live] == false) then
    pcall(self.ensure_raycast, self, live)
  end
end
function Adapter:rebind_if_replaced747(id, node, roots_opt)
  if id == nil then return false end
  local cur_ctrl = self.controls[id]
  local live = self:probe_live_handle748(id, roots_opt)
  if live == nil or live == cur_ctrl then return false end
  self:_swap_live_handle748(id, live)
  local ent = self._watch_handles748 and self._watch_handles748[id] or nil
  if ent ~= nil then
    ent.ctrl = live
    if ent.sync_tbl ~= nil then ent.sync_tbl[id] = live end
  end
  local bnode = node or (ent and ent.kind == "adapter" and ent.payload) or (self._bound_nodes747 and self._bound_nodes747[id]) or (self.handlers and self.handlers[id])
  if bnode ~= nil and bnode.event ~= nil and (bnode.kind == "button" or bnode.kind == "cursor") then
    pcall(self.bind_input, self, id, bnode)
  elseif ent ~= nil and ent.kind == "util" and ent.owner ~= nil and ent.payload ~= nil then
    pcall(ent.owner._bind, ent.owner, id, ent.payload, live, ent.sync_tbl)
  end
  return true
end
function Adapter:_watch_relevant748(id, screen)
  if type(id) ~= "string" then return false end
  if screen == "home" then
    return id:sub(1, 5) == "home." or id:sub(1, 8) == "td.home." or id:sub(1, 9) == "block640."
  elseif screen == "select" then
    return id:sub(1, 7) == "select." or id:sub(1, 11) == "hit.select." or id:sub(1, 6) == "modal." or id:sub(1, 9) == "block640."
  elseif screen == "shop" or screen == "bag" then
    return id:sub(1, 5) == "econ." or id:sub(1, 9) == "block640."
  else
    -- 关内（screen == nil 或 "level"）：排除首页/选关/商城专用按钮，覆盖 clues.*/hint635.*/help617.*/hex.*/hit.*/cell.*/td.l1/l2/modal/result
    local b = id:byte(1) or 0
    if (b == 104 and id:sub(1, 5) == "home.") or (b == 115 and id:sub(1, 7) == "select.")
       or (b == 104 and id:sub(1, 11) == "hit.select.") or (b == 101 and id:sub(1, 5) == "econ.") then
      return false
    end
    return true
  end
end
function Adapter:check_watched_handles748(screen, ctrl_opt)
  local w = self._watch_handles748
  if w == nil then return false end
  if game == nil or game.GetClientUIRoots == nil then return false end
  local ok_r, roots = pcall(game.GetClientUIRoots)
  if not ok_r or type(roots) ~= "table" then return false end
  local hid = self._hidden_ids
  local any_rebound = false
  for bid, ent in pairs(w) do
    if self:_watch_relevant748(bid, screen) and (hid == nil or not hid[bid]) then
      local live = self:probe_live_handle748(bid, roots)
      if live ~= nil and live ~= ent.ctrl then
        self:_swap_live_handle748(bid, live)
        ent.ctrl = live
        if ent.sync_tbl ~= nil then ent.sync_tbl[bid] = live end
        if ent.kind == "adapter" then
          local bnode = ent.payload or (self.handlers and self.handlers[bid])
          if bnode ~= nil then pcall(self.bind_input, self, bid, bnode) end
          if ctrl_opt ~= nil and ctrl_opt._props ~= nil then ctrl_opt._props[bid] = nil end
          any_rebound = true
        elseif ent.kind == "util" and ent.owner ~= nil and ent.payload ~= nil then
          pcall(ent.owner._bind, ent.owner, bid, ent.payload, live, ent.sync_tbl)
          any_rebound = true
        end
      end
    end
  end
  if any_rebound and ctrl_opt ~= nil then ctrl_opt.dirty = true end
  return any_rebound
end
function Adapter:find(name)
  local hit0 = self.controls[name]
  if hit0 ~= nil then return hit0 end
  local miss = self._misses
  if miss ~= nil then
    local stamp = miss[name]
    if stamp ~= nil then
      if stamp == false or self.clock < stamp then return nil end
    end
  end
  if game == nil or game.GetClientUIRoots == nil then return nil end
  local roots = game.GetClientUIRoots()
  if roots then
    if self.cfg == nil or self.cfg.find_index ~= false then
      local rc = self._root_cache748
      if rc == nil then rc = {}; self._root_cache748 = rc end
      local hit = path_lookup_655(roots, name, rc)`
);

// ── 7. B5：切屏当帧与 2s 保活统一调用 check_watched_handles748，并让 bind_input 与 util:_bind 统一登记 ──
patch(
  'B5_切屏当帧统一检查当前页全部看护句柄',
  `        adapter._mark_layer_dirty745 = true
      end
    end
  end`,
  `        adapter._mark_layer_dirty745 = true
        -- 748（B5/U7）：同关切屏当帧对当前页全部已绑交互控件（含 Adapter:bind_input、util:_bind 与 cell.*）执行一次 O(1) 句柄换绑检查。
        if adapter.check_watched_handles748 ~= nil then
          pcall(adapter.check_watched_handles748, adapter, self.screen, self)
        end
      end
    end
  end`
);

patch(
  'B5_OnUpdate_2s保活走统一check_watched_handles748',
  `      -- 747（P1-1）：每 2s 对当前未隐藏的已绑交互按钮做 O(1) 静态路径句柄抽检（0 次 GetChildren）；
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
      end`,
  `      -- 748（B5/U7）：每 2s 通过统一看护管理器抽检当前页活跃交互控件（覆盖 Adapter:bind_input、util:_bind 与 cell.*，0 次 GetChildren）。
      if adapter._watch_handles748 ~= nil and adapter.check_watched_handles748 ~= nil then
        local ctrl748 = session and session.controller
        pcall(adapter.check_watched_handles748, adapter, ctrl748 and ctrl748.screen or nil, ctrl748)
      end`
);

patch(
  'B5_bind_input统一向watch_handles748登记',
  `  if not was_bound747 and self:has_static_route747(id) and self.ensure_raycast ~= nil and not (self._ray_want and self._ray_want[ctrl] == false) then
    pcall(self.ensure_raycast, self, ctrl)
  end`,
  `  if not was_bound747 and self.ensure_raycast ~= nil and not (self._ray_want and self._ray_want[ctrl] == false)
     and (self:has_static_route747(id) or (type(id) == "string" and id:sub(1, 5) == "cell.")) then
    pcall(self.ensure_raycast, self, ctrl)
  end`
);

patch(
  'B5_bind_input尾部登记静态与动态cell交互句柄',
  `  if self:has_static_route747(id) then
    self._bound_nodes747 = self._bound_nodes747 or {}
    self._bound_nodes747[id] = node
  end`,
  `  if self:has_static_route747(id) or (type(id) == "string" and id:sub(1, 5) == "cell.") then
    self:register_watch_handle748(id, ctrl, "adapter", node, nil, nil)
  end`
);

patch(
  'B5_util_bind统一向adapter看护管理器登记并传递sync_tbl',
  `function M:_bind(name, fn, resolved)
  local ctrl = resolved or self:_find(name)
  if ctrl == nil or self.bound[ctrl] then return ctrl ~= nil end
  if ctrl.AddCursorEventListener == nil then return false end
  local ok = pcall(function()
    local ev = Enum and Enum.CursorEventType and Enum.CursorEventType.CursorClick
    if ev == nil then error("CursorClick unavailable") end
    pcall(function() ctrl.raycastTarget = true end)
    pcall(function() ctrl.interactable = true end)
    ctrl:AddCursorEventListener(ev, function() fn() end)
  end)
  if ok then self.bound[ctrl] = true end
  return ok
end`,
  `function M:_bind(name, fn, resolved, sync_tbl)
  local ctrl = resolved or self:_find(name)
  if ctrl == nil or self.bound[ctrl] then return ctrl ~= nil end
  if ctrl.AddCursorEventListener == nil then return false end
  local ok = pcall(function()
    local ev = Enum and Enum.CursorEventType and Enum.CursorEventType.CursorClick
    if ev == nil then error("CursorClick unavailable") end
    pcall(function() ctrl.raycastTarget = true end)
    pcall(function() ctrl.interactable = true end)
    ctrl:AddCursorEventListener(ev, function() fn() end)
  end)
  if ok then
    self.bound[ctrl] = true
    if self.adapter ~= nil and self.adapter.register_watch_handle748 ~= nil then
      self.adapter:register_watch_handle748(name, ctrl, "util", fn, self, sync_tbl)
    end
  end
  return ok
end`
);

patch(
  'B5_help617与hint635传入sync_tbl同步新句柄',
  `  if not help617.close_bound and c["help617.close.hit"] ~= nil then
    help617.close_bound = util:_bind("help617.close.hit", close, c["help617.close.hit"])
  end
  if not help617.entry_bound and c["clues.help627.hit"] ~= nil then
    help617.entry_visible = nil
    help617.entry_bound = util:_bind("clues.help627.hit", function()`,
  `  if not help617.close_bound and c["help617.close.hit"] ~= nil then
    help617.close_bound = util:_bind("help617.close.hit", close, c["help617.close.hit"], c)
  end
  if not help617.entry_bound and c["clues.help627.hit"] ~= nil then
    help617.entry_visible = nil
    help617.entry_bound = util:_bind("clues.help627.hit", function()`
);

patch(
  'B5_help617_entry与home与hint635传入sync_tbl',
  `      help_visible(c["help617"], true)
    end, c["clues.help627.hit"])
  end
  if help617.entry_bound and help617.logged_generation ~= generation then
    help617.logged_generation = generation
  end
  if not help617.home_bound and c["home.tutorial627.hit"] ~= nil then
    help617.home_bound = util:_bind("home.tutorial627.hit", function()
      local cur = Murdoku.current()
      if current_tut_key() ~= "home" or overlay_open() or (cur and cur.controller and cur.controller.modal ~= nil) then return end
      local inst = tutorial_instance(TUT_SETS.home)
      if inst then
        inst:init()
        Murdoku.record_tutorial('home')
        inst:go(1)
        inst:open_ui()
      end
    end, c["home.tutorial627.hit"])
  end`,
  `      help_visible(c["help617"], true)
    end, c["clues.help627.hit"], c)
  end
  if help617.entry_bound and help617.logged_generation ~= generation then
    help617.logged_generation = generation
  end
  if not help617.home_bound and c["home.tutorial627.hit"] ~= nil then
    help617.home_bound = util:_bind("home.tutorial627.hit", function()
      local cur = Murdoku.current()
      if current_tut_key() ~= "home" or overlay_open() or (cur and cur.controller and cur.controller.modal ~= nil) then return end
      local inst = tutorial_instance(TUT_SETS.home)
      if inst then
        inst:init()
        Murdoku.record_tutorial('home')
        inst:go(1)
        inst:open_ui()
      end
    end, c["home.tutorial627.hit"], c)
  end`
);

patch(
  'B5_hint635_bind传入sync_tbl',
  `          h.bound[name]=util:_bind(name,function()
            local c=Murdoku.current()
            if c and c.controller then c.controller:hint635_action(chosen); tick_hint635() end
          end,h.controls[name])`,
  `          h.bound[name]=util:_bind(name,function()
            local c=Murdoku.current()
            if c and c.controller then c.controller:hint635_action(chosen); tick_hint635() end
          end,h.controls[name],h.controls)`
);

// ── 8. B1：enable_raycast 恢复 RAY_IDLE_STOP=3、移除早停，并剪枝后续确认趟的纯美术叶容器 ──
patch(
  'B1_enable_raycast恢复RAY_IDLE_STOP为3并取消早停与确认趟跳过静态美术叶',
  `local RAY_IDLE_STOP = 1
local RAY_MAX_SCANS = 25
function Adapter:rearm_raycast(why)
  local st = self._ray
  if st == nil then return end
  if st.scans == 0 and not st.done and st.retry_nodes == nil then return end
  st.scans, st.idle, st.done, st.retry_nodes = 0, 0, false, nil
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
  local set, seen, errs, samples = 0, 0, 0, {}
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
      st.done = true`,
  `-- 748（B1）：恢复 RAY_IDLE_STOP = 3 且移除 scans==1 / was_retry_pass 早停，确保首屏后晚挂入任何业务容器的新按钮均能被自动开启射线；
-- 首趟全树扫描完毕后，后续确认趟仅跳过已扫清的纯静态只读画片叶容器（不含 root/home/select/stage/clues/modal/econ/td），
-- 兼顾 742v12 等价的 3 趟安全观察窗与低冷启/零稳态负载。
local RAY_IDLE_STOP = 3
local RAY_MAX_SCANS = 25
local RAY_STATIC_DECOR748 = {
  ["adapt715r.background"] = true,
  ["adapt715r.TR.23"] = true, ["adapt715r.TR.24"] = true,
  ["adapt715r.TR.25"] = true, ["adapt715r.BR.26"] = true,
  ["adapt715r.BR.27"] = true, ["adapt715r.BR.28"] = true,
  ["adapt715r.WAX.12"] = true,
  ["art642.select.backdrop"] = true,
  ["select.thumb.pool"] = true,
  ["art685.mark.overlay"] = true,
  ["police-v19"] = true,
}
function Adapter:rearm_raycast(why)
  local st = self._ray
  if st == nil then return end
  if st.scans == 0 and not st.done and st.retry_nodes == nil then return end
  -- 748（B1 零额外负载优化）：仅在根句柄变更或冷启时才重扫纯静态美术画片大容器；同根下新增业务控件只需复扫动态业务容器。
  st.scans, st.idle, st.done, st.retry_nodes = 0, 0, false, nil
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
    st = { scans = 0, idle = 0, done = false, seen = 0, set = 0, announced = false, full_done748 = false }
    self._ray = st
  end
  if st.done then return st.seen, st.set, {} end
  local root = self:find("root")
  if root == nil then return 0, 0, {} end
  local set, seen, errs, samples = 0, 0, 0, {}
  local failed_nodes = nil
  local visited = {}
  local ray_want = self._ray_want
  if st.last_root748 ~= root then
    st.full_done748 = false
    st.leaf_ok748 = setmetatable({}, { __mode = "k" })
    st.last_root748 = root
  end
  local leaf_ok = st.leaf_ok748
  if leaf_ok == nil then
    leaf_ok = setmetatable({}, { __mode = "k" })
    st.leaf_ok748 = leaf_ok
  end
  local skip_decor = (st.full_done748 == true)
  local function walk(c, depth)
    if c == nil or depth > 20 or visited[c] then return end
    visited[c] = true
    local want = not (ray_want and ray_want[c] == false)
    if skip_decor and depth > 0 then
      if leaf_ok[c] == want then
        local ok_l, before_l, did_l = pcall(p748_ray_leaf_step, c, want)
        if ok_l and before_l ~= nil then
          seen = seen + 1
          if did_l then set = set + 1 end
          return
        end
        leaf_ok[c] = nil
      end
      local ok_dn, dnm = pcall(p744_name, c)
      if ok_dn and type(dnm) == "string" and (RAY_STATIC_DECOR748[dnm]
          or dnm:sub(1, 16) == "grp653.static.1."
          or (dnm:sub(1, 3) == "td." and dnm:find("%.page%.%d+$") ~= nil)) then
        local ok_b, before = pcall(p744_ray_get, c)
        if ok_b and before ~= nil then
          seen = seen + 1
          if before ~= want then
            if pcall(p744_ray_set, c, want) == true then set = set + 1 end
          end
        end
        return
      end
    end
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
    elseif depth > 0 and type(kids) == "table" and #kids == 0 and before ~= nil then
      -- 首趟确认是终端空叶节点（无子控件、无报错），后续确认趟省去空 GetChildren() 分配，仍核查自身 raycastTarget。
      leaf_ok[c] = want
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
    if not was_retry_pass and seen > 0 then st.full_done748 = true end
    local eff_seen = was_retry_pass and math.max(seen, st.seen or 0) or seen
    if eff_seen > 0 and set == 0 and not was_retry_pass then st.idle = st.idle + 1 else st.idle = 0 end
    if eff_seen > 0 and st.idle >= RAY_IDLE_STOP then
      st.done = true`
);

// ── 9. B9：enable_cursor 取消缺项永久放弃（O(1) 静态路由退避探活） ──────────
patch(
  'B9_enable_cursor取消缺项6趟永久放弃改O1退避探活',
  `  local need_idle = (found >= #CURSOR_CONTAINERS) and 3 or 6
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
  end
  return n
end
function Adapter:rearm_cursor(why)
  local st = self._cursor
  if st == nil then return end
  if not st.done and st.idle == 0 and st.n == 0 then return end    
  st.idle, st.done = 0, false`,
  `  -- 748（B9）：CURSOR_CONTAINERS 全部 6 个容器在真实 .gil 均存在且走 O(1) 静态路由；
  -- 仅在全部齐备且连续 3 趟 showCursor==true 时才收敛，缺项绝不永久放弃（改按 20→40→60 帧仅 O(1) 探活缺失项）。
  if found >= #CURSOR_CONTAINERS and present_all_true then
    st.missing748 = nil
    st.miss_wait748 = 0
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
    local miss_list = nil
    for i = 1, #CURSOR_CONTAINERS do
      if self.controls[CURSOR_CONTAINERS[i]] == nil then
        miss_list = miss_list or {}
        miss_list[#miss_list + 1] = CURSOR_CONTAINERS[i]
      end
    end
    st.missing748 = miss_list
    st.miss_polls748 = (st.miss_polls748 or 0) + 1
    st.miss_wait748 = (st.miss_polls748 <= 3) and 1 or ((st.miss_polls748 <= 8) and 2 or 3)
  end
  return n
end
function Adapter:rearm_cursor(why)
  local st = self._cursor
  if st == nil then return end
  if not st.done and st.idle == 0 and st.n == 0 and st.missing748 == nil then return end
  st.idle, st.done, st.missing748, st.miss_polls748, st.miss_wait748 = 0, false, nil, 0, 0`
);

patch(
  'B9_enable_cursor缺项期间仅O1静态探活不重复扫描',
  `  local st = self._cursor
  if st == nil then
    st = { idle = 0, done = false, n = 0 }
    self._cursor = st
  end
  self:prefetch(CURSOR_CONTAINERS)`,
  `  local st = self._cursor
  if st == nil then
    st = { idle = 0, done = false, n = 0 }
    self._cursor = st
  end
  -- 748（B9）：若前次仅差少数晚挂容器，在退避间隔内直接返回，到期只做 O(1) probe_static747（0 次 GetChildren）。
  if st.missing748 ~= nil and #st.missing748 > 0 then
    st.miss_tick748 = (st.miss_tick748 or 0) + 1
    if st.miss_tick748 < (st.miss_wait748 or 1) then
      return st.n or 0
    end
    st.miss_tick748 = 0
    local any_new = false
    for i = 1, #st.missing748 do
      local mname = st.missing748[i]
      local live = self:probe_static747(mname)
      if live ~= nil then
        self.controls[mname] = live
        self:_note_lookup_hit(mname)
        if self._misses ~= nil then self._misses[mname] = nil end
        any_new = true
      end
    end
    if not any_new then
      st.miss_polls748 = (st.miss_polls748 or 0) + 1
      st.miss_wait748 = (st.miss_polls748 <= 3) and 1 or ((st.miss_polls748 <= 8) and 2 or 3)
      return st.n or 0
    end
  end
  self:prefetch(CURSOR_CONTAINERS)`
);

// ── 10. U11：_mark_all_ctrls 与 _mark_hide_all 使用构建期从 .gil 推导的真实标点数 ──
patch(
  'U11_mark_all_ctrls使用自动推导的标点数',
  `  if #t >= 192 then self._mark_ctl_cache = t end   -- 控件树未就绪时不缓存，下次重建
  return t
end
function Adapter:_mark_hide_all()
  if self._mark_screen_on == false and self._mark_all_hidden_gen745 == self._lookup_gen then return end
  local t = self:_mark_all_ctrls()
  for i = 1, #t do
    pcall(p745_set_vis_false, t[i])
  end
  self._mark_screen_on = false
  if #t >= 192 then self._mark_all_hidden_gen745 = self._lookup_gen end
end`,
  `  if #t >= ${markCtrlCount} then self._mark_ctl_cache = t end   -- 748(U11)：由构建期从 .gil 真实树自动推导
  return t
end
function Adapter:_mark_hide_all()
  if self._mark_screen_on == false and self._mark_all_hidden_gen745 == self._lookup_gen then return end
  local t = self:_mark_all_ctrls()
  for i = 1, #t do
    pcall(p745_set_vis_false, t[i])
  end
  self._mark_screen_on = false
  if #t >= ${markCtrlCount} then self._mark_all_hidden_gen745 = self._lookup_gen end
end`
);

// ── 11. B2 / B3：set_property("visible") 与 set_property("raycast") 严格单属性隔离 + 失败返回 false ──
patch(
  'B3_set_property_visible严格单属性隔离且失败不锁缓存',
  `    local vis = value and true or false
    local ok_vg747, prev_vis747 = pcall(p745_set_vis_guard, ctrl, vis)`,
  `    local vis = value and true or false
    if vis then pcall(p748_set_active_true, ctrl) end
    local ok_vg747, prev_vis747 = pcall(p748_set_vis_if, ctrl, vis)`
);

patch(
  'B2_B3_set_property_visible失败返false与raycast三项独立pcall',
  `      local w = (self._edge_want ~= nil) and self._edge_want[id] or nil
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
    pcall(p745_set_ray_guard, ctrl, want)`,
  `      local w = (self._edge_want ~= nil) and self._edge_want[id] or nil
      if w ~= nil then
        for name, want in pairs(w) do
          local s2 = self:sub(id, name)
          if s2 ~= nil then p745_set_vis_guard(s2, want) end
        end
      end
    end
    if not ok_vg747 then return false end
  elseif key == "raycast" then
    local want = value and true or false
    self._ray_want = self._ray_want or setmetatable({}, { __mode = "k" })
    self._ray_want[ctrl] = want
    -- 748（B2/U6）：三项属性各自独立无闭包 pcall，首项抛错绝不跳过后两项，且任一失败返回 false 阻止 _props 锁死缓存。
    local ok1 = pcall(p748_set_bool_prop, ctrl, "raycastTarget", want)
    local ok2 = pcall(p748_set_bool_prop, ctrl, "blockRaycast", want)
    local ok3 = pcall(p748_set_bool_prop, ctrl, "interactable", want)
    if not (ok1 and ok2 and ok3) then return false end`
);

// 清理剩余 5 处对 p745_set_vis_guard 的 pcall 包装（p745_set_vis_guard 内部已是两次独立 pcall，省掉冗余外层 pcall）
patch(
  'B3_mark与image与face子项直接调用单属性隔离p745_set_vis_guard',
  `  local c0 = self:find(base); if c0 ~= nil then pcall(p745_set_vis_guard, c0, on) end
  local c1 = self:find(base .. ".stroke.0"); if c1 ~= nil then pcall(p745_set_vis_guard, c1, on) end
  local c2 = self:find(base .. ".stroke.1"); if c2 ~= nil then pcall(p745_set_vis_guard, c2, on) end`,
  `  local c0 = self:find(base); if c0 ~= nil then p745_set_vis_guard(c0, on) end
  local c1 = self:find(base .. ".stroke.0"); if c1 ~= nil then p745_set_vis_guard(c1, on) end
  local c2 = self:find(base .. ".stroke.1"); if c2 ~= nil then p745_set_vis_guard(c2, on) end`
);

patch(
  'B3_image分支调用单属性隔离p745_set_vis_guard',
  `        pcall(p745_set_vis_guard, target, true)`,
  `        p745_set_vis_guard(target, true)`
);

patch(
  'B3_cell_face调用单属性隔离p745_set_vis_guard',
  `      if ok_f and face ~= nil then pcall(p745_set_vis_guard, face, true) end`,
  `      if ok_f and face ~= nil then p745_set_vis_guard(face, true) end`
);

// ── 12. B8：murdoku_set_vis 恢复 forcing 60 帧强写语义 + cell.* 确保拿到 stage 主容器 ──
patch(
  'B8_murdoku_set_vis恢复forcing强写语义与cell主容器解析',
  `local function murdoku_set_vis(ad, nm, want, forcing, memo)
  if ad == nil then return 0 end
  local c = ad.controls and ad.controls[nm] or nil
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
  end
  if c == nil then return 0 end
  local ok_w, did = pcall(m745_vis_sync, c, want)
  if ok_w then
    memo[nm] = want
    return did and 1 or 0
  end
  return 0
end`,
  `local function murdoku_set_vis(ad, nm, want, forcing, memo)
  if ad == nil then return 0 end
  local c = ad.controls and ad.controls[nm] or nil
  if c == nil then
    -- 748（B8）：稳态（非 forcing）查找 cell.* 时先 O(1) 定位 board/stage（含 stage 静态路由兜底），
    -- 主容器已就绪时直接 GetChild，仅当主容器尚不存在时才回退 ad:find，既防漏管又避免全树索引重建。
    if not forcing and type(nm) == "string" and nm:sub(1, 5) == "cell." then
      local host = (ad.controls and (ad.controls["board"] or ad.controls["stage"])) or nil
      if host == nil and ad.probe_static747 ~= nil then
        host = ad:probe_static747("stage")
        if host ~= nil and ad.controls ~= nil then ad.controls["stage"] = host end
      end
      if host ~= nil and host.GetChild ~= nil then
        local ok_g, child = pcall(host.GetChild, host, nm)
        if ok_g and child ~= nil then
          ad.controls[nm] = child
          c = child
        end
      end
      if c == nil and host ~= nil then return 0 end
    end
    if c == nil then
      local misses = ad._misses
      if misses ~= nil then
        local stamp = misses[nm]
        if stamp == false or (type(stamp) == "number" and (ad.clock or 0) < stamp) then return 0 end
      end
      local ok_f, res_f = pcall(ad.find, ad, nm)
      if ok_f then c = res_f end
    end
  end
  if c == nil then return 0 end
  -- 748（B8）：forcing（切屏 60 帧窗口）严格恢复 742v12 无视回读强写 SetVisible 语义，对抗引擎属性/渲染脱节；
  -- 稳态（forcing == false）仍走 m745_vis_sync 读回守卫，0 无效写。
  if forcing then
    if pcall(m744_vis_set, c, want) then
      memo[nm] = want
      return 1
    end
    return 0
  end
  local ok_w, did = pcall(m745_vis_sync, c, want)
  if ok_w then
    memo[nm] = want
    return did and 1 or 0
  end
  return 0
end`
);

// ── 13. B9 / B3：教程 M:_ensure_furniture 取消整代永久放弃 + t745_set_vis 拆分单操作隔离 ──
patch(
  'B9_教程furniture取消永久跳过改轻量退避探活',
  `function M:furniture_done()
  local spec = FURN[self.tag]
  if spec == nil then return true end
  local cur_gen = self.adapter and self.adapter._lookup_gen or 0
  if self._furn_skip_gen745 == cur_gen then return true end
  if self.furniture == nil then return false end
  for i = 1, #spec do if self.furniture[i] == nil then return false end end
  return true
end
function M:_ensure_furniture(limit)
  local spec = FURN[self.tag]
  if spec == nil or game == nil or game.InstantiateClientUIControl == nil then return end
  local parent = self:_find(self.root_name .. ".board")
  if parent == nil then
    self._furn_skip_gen745 = self.adapter and self.adapter._lookup_gen or 0
    if not self._furn_skip_logged745 then
      self._furn_skip_logged745 = true
      self:_note("家具实例化跳过 tag=" .. self.tag .. "：找不到 " .. self.root_name .. ".board")
    end
    return
  end`,
  `function M:furniture_done()
  local spec = FURN[self.tag]
  if spec == nil then return true end
  if self.furniture == nil then return false end
  for i = 1, #spec do if self.furniture[i] == nil then return false end end
  return true
end
function M:_ensure_furniture(limit)
  local spec = FURN[self.tag]
  if spec == nil or game == nil or game.InstantiateClientUIControl == nil then return end
  local ad = self.adapter
  local now = (ad and ad.clock) or 0
  local bname = self.root_name .. ".board"
  local parent = nil
  if self._furn_retry_at748 ~= nil and now < self._furn_retry_at748 then
    -- 748（B9）：board 暂缺时不整代锁死，若已通过 O(1) 静态路由挂回则立刻继续，未挂回则跳过本帧开销。
    if ad ~= nil and ad.probe_static747 ~= nil then
      parent = ad:probe_static747(bname)
      if parent ~= nil then ad.controls[bname] = parent end
    end
    if parent == nil then return end
  end
  if parent == nil then parent = self:_find(bname) end
  if parent == nil then
    local tries = (self._furn_miss_tries748 or 0) + 1
    self._furn_miss_tries748 = tries
    local gap = (tries <= 2) and 0.25 or ((tries <= 5) and 0.5 or 1.0)
    self._furn_retry_at748 = now + gap
    if not self._furn_skip_logged745 then
      self._furn_skip_logged745 = true
      self:_note("家具实例化等待 tag=" .. self.tag .. "：暂找不到 " .. bname .. "（退避重试）")
    end
    return
  end
  self._furn_retry_at748 = nil
  self._furn_miss_tries748 = 0`
);

patch(
  'B3_t745_set_vis拆分为单操作独立pcall',
  `local function t745_set_vis(ctrl, want)
  if ctrl.visible ~= want then ctrl:SetVisible(want) end
  if want and ctrl.active ~= true then ctrl:SetActive(true) end
end`,
  `local function t748_set_vis_only(ctrl, want)
  if ctrl.visible ~= want then ctrl:SetVisible(want) end
end
local function t748_set_act_true(ctrl)
  if ctrl.active ~= true then ctrl:SetActive(true) end
end`
);

patch(
  'B3_Tutorial_visible调用独立pcall',
  `function M:_visible(name, want)
  local ctrl = self:_find(name)
  if ctrl == nil then return false end
  pcall(t745_set_vis, ctrl, want and true or false)
  return true
end`,
  `function M:_visible(name, want)
  local ctrl = self:_find(name)
  if ctrl == nil then return false end
  local w = want and true or false
  local ok_v = pcall(t748_set_vis_only, ctrl, w)
  if w then pcall(t748_set_act_true, ctrl) end
  return ok_v == true
end`
);

// ── 14. B3 / B4：e745_help_vis 拆单操作独立 pcall + sync_block640 确认条恢复每帧置顶 + 遮罩全成功才落盘 ──
patch(
  'B3_e745_help_vis拆单操作独立pcall',
  `local function e745_help_vis(c, v)
  if c.visible ~= v then
    if c.SetVisible then c:SetVisible(v) else c.visible = v end
  end
  if v and c.active ~= true then
    if c.SetActive then c:SetActive(true) end
  end
end`,
  `local function e748_help_vis_only(c, v)
  if c.visible ~= v then
    if c.SetVisible then c:SetVisible(v) else c.visible = v end
  end
end
local function e748_help_act_true(c)
  if c.active ~= true and c.SetActive then c:SetActive(true) end
end`
);

patch(
  'B3_help_visible返回成功标志且独立pcall',
  `local function help_visible(c, v)
  if c == nil then return end
  pcall(e745_help_vis, c, v)
end`,
  `local function help_visible(c, v)
  if c == nil then return false end
  local w = v and true or false
  local ok_v = pcall(e748_help_vis_only, c, w)
  if w then pcall(e748_help_act_true, c) end
  return ok_v == true
end`
);

patch(
  'B4_B3_sync_block640确认条打开期每帧置顶与遮罩单操作隔离失败即重试',
  `local function e745_set_k_block640(panel)
  if panel.showCursor ~= true then panel.showCursor = true end
  if panel.disableCursorEventPassthrough ~= true then panel.disableCursorEventPassthrough = true end
  panel:SetAsLastSibling()
end`,
  `local function e748_set_bool_if(panel, k, want)
  if panel[k] ~= want then panel[k] = want end
end
local function e748_set_k_block640(panel)
  local ok1 = pcall(e748_set_bool_if, panel, "showCursor", true)
  local ok2 = pcall(e748_set_bool_if, panel, "disableCursorEventPassthrough", true)
  local ok3 = pcall(e744_last_sib, panel)
  return ok1 and ok2 and ok3
end`
);

patch(
  'B4_sync_block640确认条恢复打开期每帧缓存置顶',
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
      e.last_pend745 = pend`,
  `    elseif spec.tag == "confirm" then
      want = false
      local pend = ctrl and ctrl.pending or nil
      if e.hit_hidden745 ~= hit then
        if help_visible(hit, false) then e.hit_hidden745 = hit end
      end
      -- 748（B4/U10）：确认条仅在玩家打开确认条（pend~=nil）的 1~3 秒内活跃且仅 4 个按钮；
      -- 关闭态（pend==nil）严格 0 开销，打开态每帧用缓存句柄置顶，杜绝确认键被压在底层。
      if pend ~= nil then
        e.target_ctrls748 = e.target_ctrls748 or {}
        for ti = 1, #spec.targets do
          local button = e.target_ctrls748[ti]
          if button == nil then
            button = adapter:find(spec.targets[ti])
            e.target_ctrls748[ti] = button
          end
          if button then
            if not pcall(e744_last_sib, button) then
              e.target_ctrls748[ti] = nil
            end
          end
        end
      end
      e.last_pend745 = pend`
);

patch(
  'B4_sync_block640遮罩全成功才落盘last_want失败下帧即重试',
  `    if e.last_want745 ~= want or (btick % 60 == 0) then
      help_visible(panel, want)
      if want and panel then
        pcall(e745_set_k_block640, panel)
        for ti = 1, #spec.targets do
          local c = adapter:find(spec.targets[ti])
          if c then pcall(e744_last_sib, c) end
        end
      end
      e.last_want745 = want
    end`,
  `    if e.last_want745 ~= want or (btick % 60 == 0) then
      local ok_all = (panel == nil) or help_visible(panel, want)
      if want and panel then
        if not e748_set_k_block640(panel) then ok_all = false end
        e.target_ctrls748 = e.target_ctrls748 or {}
        for ti = 1, #spec.targets do
          local c = e.target_ctrls748[ti]
          if c == nil then
            c = adapter:find(spec.targets[ti])
            e.target_ctrls748[ti] = c
          end
          if c then
            if not pcall(e744_last_sib, c) then
              ok_all = false
              e.target_ctrls748[ti] = nil
            end
          else
            ok_all = false
          end
        end
      end
      -- 748（B4）：仅当显隐、防穿透与全部置顶均成功才落盘 last_want745；任一抛错下帧立即重试，绝不锁死 59 帧。
      e.last_want745 = ok_all and want or nil
    end`
);

// ── 15. U11 / B6：动态推导撕边/背景叶数 + 选关卡片极轻量异步文本变化字号自愈 ──
const tearLuaLiteral = '{' + tearDefs.map((t) => `{name="${t.name}",side="${t.side}",expect=${t.expect}}`).join(',') + '}';
patch(
  'U11_撕边叶数由构建期自动推导',
  `local ADAPT715R_TEARS = {{name="adapt715r.TR.23",side="tr",expect=141},{name="adapt715r.TR.24",side="tr",expect=183},{name="adapt715r.TR.25",side="tr",expect=17},{name="adapt715r.BR.26",side="bl",expect=79},{name="adapt715r.BR.27",side="bl",expect=150},{name="adapt715r.BR.28",side="bl",expect=21}}`,
  `-- 748（U11）：由 build_748.mjs 在构建期从真实 .gil 树自动推导写入，消除手写魔数。
local ADAPT715R_TEARS = ${tearLuaLiteral}
local ADAPT715R_BG_LEAVES = ${bgLeafCount}`
);

patch(
  'U11_背景叶数引用自动推导常量',
  `    if ok and type(children)=='table' and #children==649 then st.leaves=children;st.leafState=nil end`,
  `    if ok and type(children)=='table' and #children>=ADAPT715R_BG_LEAVES then st.leaves=children;st.leafState=nil end`
);

patch(
  'B6_sync_adapt715r选关稳态异步文本变更极轻量字号同步',
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
  end`,
  `  -- 748（B6）：独立极轻量卡片字号同步器：缓存 12 个卡片文本框句柄，仅在选关页做 .text 引用比对（0 字符串拼接、0 布局重跑），
  -- 即使文字由云端/外部异步改写也能在 0.25s 内自动重算字号，非选关页 0 开销。
  local function sync_card_fonts748(cscale, do_force)
    st.cardFont = st.cardFont or {}
    st.cardCtrls748 = st.cardCtrls748 or {}
    local suffixes = { 'info', 'title', 'result' }
    for i = 1, 4 do
      for si = 1, 3 do
        local suffix = suffixes[si]
        local slot_idx = (i - 1) * 3 + si
        local c = st.cardCtrls748[slot_idx]
        if c == nil then
          c = find('select.card.' .. i .. '.' .. suffix)
          st.cardCtrls748[slot_idx] = c
        end
        if c ~= nil then
          local ok_t, txt = pcall(e744_get_k, c, 'text')
          if ok_t then
            local rec = st.cardFont[slot_idx]
            if do_force or rec == nil or rec.txt ~= txt or rec.scale ~= cscale then
              local size = 16 * cscale
              if suffix ~= 'result' then
                local units = 0
                for ch_u in tostring(txt or ''):gmatch('[%z\\1-\\127\\194-\\244][\\128-\\191]*') do units = units + (#ch_u == 1 and .55 or 1) end
                size = math.min(18, math.max(10, math.floor((182 - 6) / math.max(1, units)))) * cscale
              end
              local ok_fs, cur_fs = pcall(e744_get_k, c, 'fontSize')
              if do_force or not ok_fs or cur_fs ~= size then
                if pcall(e745_set_font, c, size) then
                  st.cardFont[slot_idx] = { txt = txt, scale = cscale, size = size }
                end
              else
                st.cardFont[slot_idx] = { txt = txt, scale = cscale, size = size }
              end
            end
          else
            st.cardCtrls748[slot_idx] = nil
          end
        end
      end
    end
  end
  -- 747+748（P2-4 + B6）：若主布局已稳态且分辨率/页面/槽位/确认条/选关页码均未变：
  --   选关页先执行极轻量 12 文本脏检；无失败翻页项即早退；有失败翻页项仅定向重试失败的 1~4 项。
  if not force and not pageChanged and valid_sz and st.main_ok747==true
     and st.steady_cw==cw and st.steady_ch==ch and st.steady_slot==slot
     and st.steady_pend==pend_act and st.steady_spage==spage then
    if selecting and st.steady_cardScale748 ~= nil then
      sync_card_fonts748(st.steady_cardScale748, false)
    end
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
  'B6_sync_adapt715r主路径复用sync_card_fonts748并记录cardScale',
  `    if selecting or force then
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
                  local units=0;for ch in tostring(txt or ''):gmatch('[%z\\1-\\127\\194-\\244][\\128-\\191]*') do units=units+(#ch==1 and .55 or 1) end
                  size=math.min(18,math.max(10,math.floor((182-6)/math.max(1,units))))*cardScale
                end
                local ok_w=pcall(e745_set_font,c,size)
                if ok_w then st.cardFont[cname]={key=fkey,size=size} end
              end
            end
          end
        end
      end
    end`,
  `    if selecting or force then
      sync_card_fonts748(cardScale, force)
    end`
);

patch(
  'B6_保存steady_cardScale748并在代数重置时清理cardCtrls748',
  `  if st.main_ok747 then
    st.steady_cw=phys_cw; st.steady_ch=phys_ch; st.steady_slot=slot
    st.steady_pend=pend_act; st.steady_spage=spage
  end`,
  `  if st.main_ok747 then
    st.steady_cw=phys_cw; st.steady_ch=phys_ch; st.steady_slot=slot
    st.steady_pend=pend_act; st.steady_spage=spage
    st.steady_cardScale748=cardScale
  end`
);

patch(
  'B6_代数重置清理cardCtrls748',
  `  if gen~=st.gen then st.handles={};st.gen=gen;st.leaves=nil;st.leafState=nil;st.tearKids={};st.tearState={};st.cardFont={};st.page=nil;st.steady_ok745=false;st.main_ok747=false;st.pager_retry747=nil;st.fill_col745=nil end`,
  `  if gen~=st.gen then st.handles={};st.gen=gen;st.leaves=nil;st.leafState=nil;st.tearKids={};st.tearState={};st.cardFont={};st.cardCtrls748={};st.steady_cardScale748=nil;st.page=nil;st.steady_ok745=false;st.main_ok747=false;st.pager_retry747=nil;st.fill_col745=nil end`
);

// ── 16. 版本标记更新为 v748 ──────────────────────────────────────────────────
patch(
  '版本标记1',
  `if print then print("[murdoku] ===== 构建标记 v747 / 交互闭环与尾部消峰 =====") end`,
  `if print then print("[murdoku] ===== 构建标记 v748 / 全核查修复与自闭环验证 =====") end`
);

patch(
  '版本标记2',
  `print("[murdoku] ===== 构建标记 v747 / 交互闭环与尾部消峰 =====")`,
  `print("[murdoku] ===== 构建标记 v748 / 全核查修复与自闭环验证 =====")`
);

// ═════════════════════════════════════════════════════════════════════════════
// 四维静态门禁（U8 / U11 / U12）：
//   ① Lua 5.4 语法检查
//   ② luac -p -l 字节码全局读（GETTABUP _ENV）+ 全局写（SETTABUP _ENV）双审计（对比 742v12 与 747）
//   ③ .gil 真实控件树一致性门禁（INDEX_PRUNE748、RAY_STATIC_DECOR748、ADAPT715R_TEARS、CURSOR_CONTAINERS 100% 存在）
//   ④ 零模块级 path745_root_cache 断言 + shop_cold_render 回归
// ═════════════════════════════════════════════════════════════════════════════
const candPath = candOutArg ? path.resolve(candOutArg.slice(16)) : path.join(runTmp, 'candidate748.lua');
fs.mkdirSync(path.dirname(candPath), { recursive: true });
fs.writeFileSync(candPath, lua, 'utf8');

const syn = spawnSync('lua', ['-e', `assert(loadfile(${JSON.stringify(candPath)})); print("SYNTAX PASS")`], { encoding: 'utf8' });
assert.equal(syn.status, 0, 'Lua 语法检查失败:\n' + syn.stderr);
process.stdout.write(syn.stdout);

// ② GETTABUP + SETTABUP 双审计
function auditGlobals(srcText, tag) {
  const p = path.join(runTmp, `audit_${tag}.lua`);
  fs.writeFileSync(p, srcText, 'utf8');
  const r = spawnSync('luac', ['-p', '-l', p], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  assert.equal(r.status, 0, `luac 审计失败 (${tag}):\n` + r.stderr);
  const gets = new Set();
  const sets = new Set();
  for (const line of r.stdout.split('\n')) {
    const mg = line.match(/GETTABUP\s+\d+\s+\d+\s+\d+\s*;\s*_ENV\s+"([^"]+)"/);
    if (mg) gets.add(mg[1]);
    const ms = line.match(/SETTABUP\s+\d+\s+\d+\s+\d+\s*;\s*_ENV\s+"([^"]+)"/);
    if (ms) sets.add(ms[1]);
  }
  return { gets, sets };
}
const g742Tree = loadTree(base742);
const lua742 = findScriptLeaf(g742Tree).buf.toString('utf8');
const aud742 = auditGlobals(lua742, '742');
const aud747 = auditGlobals(original, '747');
const aud748 = auditGlobals(lua, '748');
const newGetVs747 = [...aud748.gets].filter((k) => !aud747.gets.has(k));
const newSetVs747 = [...aud748.sets].filter((k) => !aud747.sets.has(k));
const newGetVs742 = [...aud748.gets].filter((k) => !aud742.gets.has(k));
const newSetVs742 = [...aud748.sets].filter((k) => !aud742.sets.has(k));
assert.equal(newGetVs747.length, 0, '相对 747 新增未声明全局读: ' + newGetVs747.join(', '));
assert.equal(newSetVs747.length, 0, '相对 747 新增未声明全局写: ' + newSetVs747.join(', '));
assert.equal(newGetVs742.length, 0, '相对 742v12 新增未声明全局读: ' + newGetVs742.join(', '));
assert.equal(newSetVs742.length, 0, '相对 742v12 新增未声明全局写: ' + newSetVs742.join(', '));
assert(!lua.includes('path745_root_cache'), '残留模块级可变缓存 path745_root_cache');
console.log(`STATIC GATE PASS (GETTABUP+SETTABUP newVs742=0/0, newVs747=0/0, moduleRootCache=removed)`);

// ③ .gil 真实控件树一致性门禁
function checkTableNamesInGil(tableVarName) {
  const m = lua.match(new RegExp(`local ${tableVarName}\\s*=\\s*\\{([\\s\\S]*?)\\n\\}`));
  assert(m, `未找到表定义: ${tableVarName}`);
  const keys = [...m[1].matchAll(/\["([^"]+)"\]\s*=\s*true/g)].map((x) => x[1]);
  assert(keys.length > 0, `表为空: ${tableVarName}`);
  const missing = keys.filter((k) => !nodesByName.has(k));
  assert.equal(missing.length, 0, `${tableVarName} 含 .gil 中不存在的控件名: ${missing.join(', ')}`);
  return keys;
}
const pruneKeys = checkTableNamesInGil('INDEX_PRUNE748');
const rayDecorKeys = checkTableNamesInGil('RAY_STATIC_DECOR748');
{
  const cm = lua.match(/local CURSOR_CONTAINERS\s*=\s*\{([^}]+)\}/);
  assert(cm, '未找到 CURSOR_CONTAINERS');
  const cnames = [...cm[1].matchAll(/"([^"]+)"/g)].map((x) => x[1]);
  const cmiss = cnames.filter((k) => !nodesByName.has(k));
  assert.equal(cmiss.length, 0, 'CURSOR_CONTAINERS 含不存在的控件名: ' + cmiss.join(', '));
}
console.log(`GIL TREE GATE PASS (INDEX_PRUNE748=${pruneKeys.length}/${pruneKeys.length}, RAY_STATIC_DECOR748=${rayDecorKeys.length}/${rayDecorKeys.length}, derived=${JSON.stringify(derivedCounts)})`);

// ④ shop_cold_render 回归
function runCold(scriptText) {
  const r = spawnSync('lua', [path.join(repo, 'tests/shop_cold_render.lua')], { input: scriptText, encoding: 'utf8' });
  assert.equal(r.status, 0, 'shop_cold_render 失败:\n' + r.stderr);
  const m = r.stdout.match(/COLD=(\d+) WRITES=(\d+) COLD_FINDS=(\d+) FINDS=(\d+)/);
  assert(m, '未匹配到 COLD 输出: ' + r.stdout);
  return m.slice(1).map(Number);
}
const cold742 = runCold(lua742);
const cold747 = runCold(original);
const cold748 = runCold(lua);
console.log('COLD 742v12', cold742, '747', cold747, '748', cold748);
assert.equal(cold748[0], cold747[0], 'COLD 应与 747 一致');
assert(cold748[1] <= cold747[1], 'WRITES 不应高于 747');
assert.equal(cold748[2], cold747[2], 'COLD_FINDS 应与 747 一致');
assert(cold748[3] <= cold747[3], 'FINDS 不应高于 747');

const candSha = sha(Buffer.from(lua, 'utf8'));
if (isCandidate) {
  console.log('CANDIDATE OK', candPath, 'patches=', patches.length, 'sha256=', candSha);
  if (!keepTmp && !candOutArg) fs.rmSync(runTmp, { recursive: true, force: true });
  process.exit(0);
}

// ═════════════════════════════════════════════════════════════════════════════
// U2 / U4：自闭环端到端验证 —— 构建脚本亲自导出真实树并运行入库的 tests/perf_verify_748.lua
// ═════════════════════════════════════════════════════════════════════════════
const treeLuaPath = path.join(runTmp, 'tree747.lua');
const valJsonPath = path.join(runTmp, 'validation748.json');
const expRes = spawnSync('node', [path.join(repo, 'tests/export_gil_tree.mjs'), base, treeLuaPath], { encoding: 'utf8' });
assert.equal(expRes.status, 0, '导出真实控件树失败:\n' + expRes.stderr);
process.stdout.write(expRes.stdout);

// 同时把 742v12 脚本落到临时路径供 6 代统一基准与 742v12↔748 端到端差分使用
const lua742Path = path.join(runTmp, 'script742v12.lua');
fs.writeFileSync(lua742Path, lua742, 'utf8');

const verifyArgs = [
  path.join(repo, 'tests/perf_verify_748.lua'),
  treeLuaPath,
  lua742Path,
  path.join(repo, '743_全面性能优化/743_内嵌脚本.lua'),
  path.join(repo, '745_解禁全面优化/745_内嵌脚本.lua'),
  path.join(repo, '746_评审加固与切屏消峰/746_内嵌脚本.lua'),
  path.join(repo, '747_交互闭环与尾部消峰/747_内嵌脚本.lua'),
  candPath,
  valJsonPath,
  candSha,
];
if (skipBench) verifyArgs.push('--skip-bench');
const verRes = spawnSync('lua', verifyArgs, { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
process.stdout.write(verRes.stdout || '');
if (verRes.stderr) process.stderr.write(verRes.stderr);
assert.equal(verRes.status, 0, '端到端验证 tests/perf_verify_748.lua 未通过');

const validation = JSON.parse(fs.readFileSync(valJsonPath, 'utf8'));
assert.equal(validation.schema, '748-e2e-v1', '验证报告 schema 不匹配');
assert.equal(validation.candidateSha256, candSha, '验证报告 SHA256 与当前候选不一致');
assert.equal(validation.pass, true, '独立验证未通过');
assert.equal(validation.equivalence742vs748.controlSnapshotDiffs, 0, '742v12 vs 748 全量等价差分非 0');
assert.equal(validation.equivalence747vs748.controlSnapshotDiffs, 0, '747 vs 748 全量等价差分非 0');

// 强制断言全部 B1-B10 核查专项与回归项全部通过
const requiredChecks = [
  'b1_late_raycast_after_f20',
  'b2_set_prop_raycast_isolation',
  'b3_set_prop_visible_active_isolation',
  'b3_help_and_tut_visible_isolation',
  'b4_confirm_bar_stay_on_top',
  'b4_modal_block_err_next_frame_retry',
  'b5_same_root_util_bind_help627',
  'b5_same_root_dynamic_cell_rebind',
  'b6_select_card_async_text_refit',
  'b7_pruned_container_lookup_and_typos',
  'b8_forcing_60f_force_write',
  'b9_cursor_late_right_recovery',
  'b9_tutorial_board_late_furniture',
  'b10_detached_readable_root_cache',
  'zone1_hex_back_confirm',
  'zone2_pcall_guard',
  'zone3_root_rebuild_fallback',
  'zone4_face_and_x70',
  'r2_p1_1_same_root_btn_replace',
  'r2_p1_1_same_root_btn_idle_wait',
  'r2_p1_2_gray_retry_idle_no_scroll',
  'r2_p1_3_raycast_partial_err_recovery',
  'r2_p1_4_hidden_subtree_err_requeue',
  'r2_p2_1_cur_vis_dedup_active',
  'r2_p2_2_econ_missing_getter_no_lock',
  'r2_p2_3_late_box_recovery',
  'r2_p2_4_pager_fail_isolated_retry',
  'r2_wait_shop_missing_fast_recover',
];
for (const ck of requiredChecks) {
  assert(validation.checks && validation.checks[ck] && validation.checks[ck].pass === true, `专项校验未通过: ${ck}`);
}

// ── 原子写入 .gil 并输出全部正式交付物 ──────────────────────────────────────
leaf.field.payload = Buffer.from(lua, 'utf8');
leaf.field.len = leaf.field.payload.length;
leaf.field.sub = null;

fs.mkdirSync(path.dirname(out), { recursive: true });
const recordBytes = new Map(g.recs.map((r) => [r.id, encodeMsg([r.field])]));
const report = writeGil(g, out, {
  label: '748 全核查修复与自闭环验证',
  expectDiffs: 1,
  expectMarker: 'v748',
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
fs.writeFileSync(path.join(outDir, '748_内嵌脚本.lua'), lua, 'utf8');
const summary = {
  baseVersion: '747',
  baseSha256: sha(g.src),
  baseBytes: g.src.length,
  baseline742Sha256: sha(g742Tree.src),
  scriptBytesBefore: Buffer.byteLength(original, 'utf8'),
  scriptBytesAfter: Buffer.byteLength(lua, 'utf8'),
  candidateSha256: candSha,
  derivedCounts,
  staticGates: {
    syntaxPass: true,
    newGlobalGetVs742: 0,
    newGlobalSetVs742: 0,
    newGlobalGetVs747: 0,
    newGlobalSetVs747: 0,
    moduleRootCacheRemoved: true,
    gilPruneContainersVerified: pruneKeys.length,
    gilRayDecorVerified: rayDecorKeys.length,
  },
  patches,
  cold: { v742v12: cold742, v747: cold747, v748: cold748 },
  records: g.recs.length,
  outputBytes: report.bytes,
  outputSha256: sha(report.g2.src),
  controlRecordsChanged: 0,
  fieldDifferences: report.diffs,
  validation,
  limits: [
    '全部验证与 6 代（742v12/743/745/746/747/748）5 轮采样基准已正式入库为 tests/export_gil_tree.mjs 与 tests/perf_verify_748.lua，并由 tools/build_748.mjs 实时执行强断言后原子落盘，可直接独立复现',
    '离线高仿真环境基于导出自真实 .gil 的 8,578 节点控件树，已补充按引擎跨界类别拆分的调用计数（GetChildren/GetChild/SetVisible/Transform/pcall），但仍未导入千星奇域客户端真机实测，移动端真实帧时、合批重绘与 RSS 仍需真机 A/B 验收',
    '仓库 lua/ 源码树停留在 715 之前（636 KB / 15,451 行，缺少 ADAPT715R 与 sync_econ742 等 716–742 业务逻辑），748 在 747 基础上派生并保持 0 控件记录改动',
  ],
};
fs.writeFileSync(path.join(outDir, '748_性能与验证.json'), JSON.stringify(summary, null, 2), 'utf8');
console.log('OUTPUT', out, report.bytes, sha(report.g2.src));

if (!keepTmp) fs.rmSync(runTmp, { recursive: true, force: true });
