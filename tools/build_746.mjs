// 746：从 745_解禁全面优化.gil 派生，仅修改内嵌 Lua，不覆盖基准或旧存档。
// 基于提交 1056f21aca21《744、745 性能优化独立评审》的六项改进建议（3 项 P1 + 3 项 P2）
// 以及切屏尾部 GetChildren 热点定位，完成恢复闭环加固与切屏长尾消除：
//   P1-1：格子巡检缺项（缺 face/x/box）保留 60 帧低频重查，仅对不完整格子重查，不扰动已齐全格子；
//   P1-2：线索灰层 _grid_disable_gray_raycast 逐属性独立受保护写入并回读确认全关后才置 gray_noray=true；
//   P1-3：选关翻页 4 控件（LM.19/RM.20/hit.select.prev/next）定位结果纳入 steady_ok，失败项每 0.25s 单独重试；
//   P2-1：撕边 6 组按真实预期叶数（141/183/17/79/150/21）判定完整，未齐组每 0.25s 复查，已齐组零重枚举；
//   P2-2：sync_econ742 首次/签名变更写入后回读位置/缩放/显隐，全部命中目标值才缓存 steady 签名；
//   P2-3：_pending_retry 调度改为按缺失控件的下次探测到期时间触发，到期先探活命中再重绘，避免每秒空转 build_layout；
//   Bonus：消除切屏时非关内 _apply_furn_level 查询缺失 "fart.furn" 触发的 8,578 节点全树 DFS 与每切屏 4,513 次隐藏子树重复枚举。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { loadTree, findScriptLeaf, writeGil } from './gil/gilwrite.mjs';
import { encodeMsg } from './gil/gilread.mjs';

const repo = fileURLToPath(new URL('../', import.meta.url));
const temp = process.env.FEIBO_TMP || 'C:/Users/18182/AppData/Local/Temp/feibo/a449b716-24f7-4e04-ab7b-67560f2af9d6';
const out = path.resolve(process.argv[2] && !process.argv[2].startsWith('--')
  ? process.argv[2]
  : path.join(repo, '746_评审加固与切屏消峰/746_评审加固与切屏消峰.gil'));
const base = path.join(repo, '745_解禁全面优化/745_解禁全面优化.gil');
const isCandidate = process.argv.includes('--candidate');
if (!isCandidate) assert(!fs.existsSync(out), '输出已存在，拒绝覆盖：' + out);

const sha = (b) => createHash('sha256').update(b).digest('hex');
const g = loadTree(base);
const leaf = findScriptLeaf(g);
const original = leaf.buf.toString('utf8');
assert.equal(sha(g.src), 'fb2822bad1f1a31d695c205d73d0f75cd340879e9878bee9e32d2b0c6ff96fa0', '基准 745 SHA256 不匹配');

let lua = original;
const patches = [];
function patch(tag, before, after) {
  const parts = lua.split(before);
  assert.equal(parts.length, 2, `补丁不唯一或未命中 [${tag}] (matches=${parts.length - 1})`);
  lua = lua.replace(before, () => after);
  patches.push(tag);
}

// ── 1. P1-2：线索灰层逐属性独立 pcall + 全部确认关闭后才标 gray_noray=true ──
patch(
  'P1-2_线索灰层逐属性受保护关闭与回读确认',
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
end`,
  `local function c746_disable_prop(cg, key)
  local v = cg[key]
  if v == nil then return true end
  if v ~= false then
    cg[key] = false
    return cg[key] == false
  end
  return true
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
  -- 746（P1-2）：逐属性独立受保护写入并读回确认，任一属性抛错或未落为 false 时不置完成，保留下一轮重试。
  local ok1, d1 = pcall(c746_disable_prop, cg, "raycastTarget")
  local ok2, d2 = pcall(c746_disable_prop, cg, "blockRaycast")
  local ok3, d3 = pcall(c746_disable_prop, cg, "interactable")
  local all_done = (ok1 and d1 == true) and (ok2 and d2 == true) and (ok3 and d3 == true)
  if rec ~= nil and all_done then rec.gray_noray = true end
  return all_done
end`
);

// ── 2. P2-3：_render_impl 记录待重试缺失控件列表，调度按缺项下次探测时间触发 ──
patch(
  'P2-3_render_impl记录待重试缺项表',
  `function Controller:_render_impl(adapter, force)
  self._pending_retry744 = false`,
  `function Controller:_render_impl(adapter, force)
  self._pending_retry744 = false
  self._pending_retry_ids746 = nil`
);

patch(
  'P2-3_render_impl收集缺项ID',
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
          end`,
  `          elseif not exists then
            if not select_content then
              last[k] = v
            else
              self._pending_retry744 = true
              self._pending_retry_ids746 = self._pending_retry_ids746 or {}
              self._pending_retry_ids746[n.id] = "missing"
            end
          else
            local why = (not exists) and "控件一直没找到（find 返回 nil）"
              or "控件在、但适配层说这次没写进去（子控件没就绪？）"
            if not select_content and retry_more(n.id, k, why, exists) == false then
              last[k] = v
            else
              self._pending_retry744 = true
              self._pending_retry_ids746 = self._pending_retry_ids746 or {}
              self._pending_retry_ids746[n.id] = "write"
            end
          end`
);

patch(
  'P2-3_render_impl矩形缺项记录ID',
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
      end`,
  `      elseif not rect_exists then
        if not select_content then
          rect_record743(last, n.rect)
        else
          self._pending_retry744 = true
          self._pending_retry_ids746 = self._pending_retry_ids746 or {}
          if self._pending_retry_ids746[n.id] == nil then self._pending_retry_ids746[n.id] = "missing" end
        end
      elseif not select_content and retry_more(n.id, "__rect", "位置没写进去（控件在，但句柄失效 / 位置被拒）", true) == false then
        rect_record743(last, n.rect)
      else
        self._pending_retry744 = true
        self._pending_retry_ids746 = self._pending_retry_ids746 or {}
        self._pending_retry_ids746[n.id] = "write"
      end`
);

// ── 3. P2-3 配套：Murdoku.on_update 按缺项下次探测到期时间轻量探活，找到才重绘 ──
patch(
  'P2-3_on_update按缺项探测到期调度免无故重绘',
  `  local sec = math.floor(current.core.elapsed or 0)
  local need_sec_render = (sec ~= current.last_tick)
    and (current.controller.screen == nil or current.controller._pending_retry744 == true)
  if need_sec_render or current.controller.dirty then
    current.last_tick = sec
    Murdoku.render()
  end`,
  `  local sec = math.floor(current.core.elapsed or 0)
  local need_sec_render = false
  if sec ~= current.last_tick then
    if current.controller.screen == nil then
      need_sec_render = true
    elseif current.controller._pending_retry744 == true then
      -- 746（P2-3）：非关内仅在写失败项或缺失项到达其 adapter._misses 探测期限时才探活；
      -- 若仅因控件缺失且探测仍未找到，则不触发整页 build_layout / render()。
      local pids = current.controller._pending_retry_ids746
      local ad_r = current.adapter
      if pids == nil or ad_r == nil then
        need_sec_render = true
      else
        local miss_tbl = ad_r._misses
        local clk = ad_r.clock or 0
        for id, kind in pairs(pids) do
          if kind == "write" then
            need_sec_render = true
            break
          else
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
          end
        end
      end
      if not need_sec_render then current.last_tick = sec end
    end
  end
  if need_sec_render or current.controller.dirty then
    current.last_tick = sec
    Murdoku.render()
  end`
);

// ── 4. Bonus-1：切屏非关内 _apply_furn_level 跳过无意义的 fart.furn 缺失扫描 ──
patch(
  'Bonus-1_非关内跳过apply_furn_level的fart.furn全树扫描',
  `function Adapter:_apply_furn_level()
  if self._furn_inst ~= nil then
    for _, v in pairs(self._furn_inst) do self:_furn_destroy(v) end
  end
  self._furn_inst = {}
  self._furn_scaled = {}
  self._furn_ok_n = 0       
  self._furn_fail_n = 0     
  self._furn_keys = {}      
  self._furn_retry_n = 0    
  self._furn_last_try = -1
  local c = self:find((self.cfg and self.cfg.furn_parent) or "board")`,
  `function Adapter:_apply_furn_level()
  if self._furn_inst ~= nil then
    for _, v in pairs(self._furn_inst) do self:_furn_destroy(v) end
  end
  self._furn_inst = {}
  self._furn_scaled = {}
  self._furn_ok_n = 0
  self._furn_fail_n = 0
  self._furn_keys = {}
  self._furn_retry_n = 0
  self._furn_last_try = -1
  -- 746：非关内（_furn_level == false）无需重查缺失家具容器或重建家具模板，直接返回，消除切屏触发的 8,578 节点全树 DFS 尖峰！
  if self._furn_level == false then
    return true
  end
  local c = self:find((self.cfg and self.cfg.furn_parent) or "board")`
);

// ── 5. Bonus-2：切屏时已隐藏控件不重复标脏隐藏子树；同关切屏保留已建 _name_idx 与 _hidden_done ──
patch(
  'Bonus-2_invalidate_lookups清隐藏子树完成缓存',
  `  self._subtree_dirty = true
  self._subtree_dirty_ids = nil
  self._baked_dirty = true`,
  `  self._subtree_dirty = true
  self._subtree_dirty_ids = nil
  self._hidden_enforced746 = nil
  self._baked_dirty = true`
);

patch(
  'Bonus-2_已隐藏控件不重复标脏隐藏子树',
  `    if vis then
      self._hidden_ids[id] = nil
      if self._subtree_dirty_ids ~= nil then self._subtree_dirty_ids[id] = nil end
    else
      self._hidden_ids[id] = true
      self._subtree_dirty_ids = self._subtree_dirty_ids or {}
      self._subtree_dirty_ids[id] = true
    end`,
  `    if vis then
      self._hidden_ids[id] = nil
      if self._subtree_dirty_ids ~= nil then self._subtree_dirty_ids[id] = nil end
      if self._hidden_enforced746 ~= nil then self._hidden_enforced746[id] = nil end
    else
      self._hidden_ids[id] = true
      if not (self._hidden_enforced746 ~= nil and self._hidden_enforced746[id] == true and cur_vis == false) then
        self._subtree_dirty_ids = self._subtree_dirty_ids or {}
        self._subtree_dirty_ids[id] = true
      end
    end`
);

patch(
  'Bonus-2_enforce_hidden_subtrees标记已完成并合并单节点pcall',
  `  local targets = full and hid or pending
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
  end`,
  `  local targets = full and hid or pending
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
  end`
);

// ── 6. P1-1：格子巡检对缺项格子保留 60 帧低频重查，仅重查缺项格子、不扰动已齐格子 ──
patch(
  'P1-1_格子巡检缺项保留低频重查不封死',
  `      local step745 = (fc745.stable >= 2) and 120 or 30
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
        end`,
  `      -- 746（P1-1）：已齐全格子保持 120 帧稳态巡检零重枚举；
      -- 任一格子缺少 face 或 x 时，仅对该缺项格子按退避周期（前 2 次 30 帧，之后 60 帧，常驻 120 帧）重查，绝不封死晚挂控件恢复。
      local step745 = (fc745.stable >= 2) and 120 or 30
      local due_incomplete746 = (fc745.has_incomplete == true) and ((f745 % 60) == 0)
      if (f745 % step745) == 0 or due_incomplete746 then
        local full_pass746 = ((f745 % step745) == 0)
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
        local function scan_cell_kids746(cell, rec)
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
        end
        local n, any_fixed, all_ready, any_incomplete = 0, false, true, false
        for r = 1, rows do
          for c = 1, cols do
            local cid = "cell." .. r .. "." .. c
            local rec = fc745.cells[cid]
            local rec_complete = (rec ~= nil and rec.face ~= nil and rec.x ~= nil)
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
                  local got_all = (rec.face ~= nil and rec.x ~= nil)
                  if not got_all then
                    -- 前 2 次间隔 30 帧，3~6 次间隔 60 帧，之后保持 120 帧低频复查，绝不永久放弃晚挂子控件。
                    local gap = (probes <= 2) and 30 or ((probes <= 6) and 60 or 120)
                    rec.next_probe746 = f745 + gap
                  else
                    rec.next_probe746 = nil
                  end
                  fc745.cells[cid] = rec
                  rec_complete = got_all
                end
                if not rec_complete then any_incomplete = true end
                local ok_s, has_face, did_fix = pcall(sync_cell745, rec)
                if not ok_s then
                  fc745.cells[cid] = nil
                  all_ready = false
                  any_incomplete = true
                else
                  if has_face then n = n + 1 end
                  if did_fix then any_fixed = true end
                end
              else
                all_ready = false
                any_incomplete = true
              end
            else
              if rec.face ~= nil then n = n + 1 end
            end
          end
        end
        fc745.has_incomplete = any_incomplete
        if full_pass746 then
          if all_ready and not any_fixed then
            fc745.stable = math.min(4, fc745.stable + 1)
          else
            fc745.stable = 0
          end
        elseif any_fixed then
          fc745.stable = 0
        end`
);

// ── 7. P1-3 & P2-1：翻页 4 控件定位结果纳入 steady_ok，撕边 6 组按预期叶数判完整 ──
patch(
  'P2-1_撕边组增加真实预期叶数',
  `local ADAPT715R_TEARS = {{name="adapt715r.TR.23",side="tr"},{name="adapt715r.TR.24",side="tr"},{name="adapt715r.TR.25",side="tr"},{name="adapt715r.BR.26",side="bl"},{name="adapt715r.BR.27",side="bl"},{name="adapt715r.BR.28",side="bl"}}`,
  `-- 746（P2-1）：记录每组撕边在存档中的真实子叶数（合计 591 叶），避免首批不完整快照被提前缓存为稳态。
local ADAPT715R_TEARS = {{name="adapt715r.TR.23",side="tr",expect=141},{name="adapt715r.TR.24",side="tr",expect=183},{name="adapt715r.TR.25",side="tr",expect=17},{name="adapt715r.BR.26",side="bl",expect=79},{name="adapt715r.BR.27",side="bl",expect=150},{name="adapt715r.BR.28",side="bl",expect=21}}`
);

patch(
  'P1-3_adapt14_pagers返回4控件完整定位状态',
  `local function adapt14_pagers(find,transform,w)
  for _,v in ipairs({{'left','adapt715r.LM.19','hit.select.prev',-1},{'right','adapt715r.RM.20','hit.select.next',1}}) do
    local art=find('art647.select.diamond.'..v[1])
    local hit=find(v[3])
    local x,y=adapt715r_pair(art,'GetAnchoredPosition')
    local hw,hh=adapt715r_pair(hit,'GetSizeDelta')
    if x and y and hw and hh and hw>0 and hh>0 then
      local center=v[4]*(w/2-12-hw/2)
      transform(v[2],center-x,0,1)
      transform(v[3],center,y,1)
    end
  end
end`,
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
end`
);

patch(
  'P1-3与P2-1_sync_adapt715r纳入翻页就绪与撕边完整叶数校验',
  `  local wax_ok=transform('adapt715r.WAX.12',0,shift,scene)
  if pending then follow_confirm717(find, pending.action) end
  adapt14_pagers(find,transform,w)
  transform('art642.select.board',0,0,1)
  local cardsOk=true
  for _,name in ipairs(ADAPT715R_SELECT_CARDS) do
    cardsOk=transform(name,0,0,cardScale) and cardsOk
  end
  -- 撕边组已重挂到art641.select末尾；显隐逐叶处理，不依赖父级级联（744：按代缓存子叶与状态）。
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
  end`,
  `  local wax_ok=transform('adapt715r.WAX.12',0,shift,scene)
  if pending then follow_confirm717(find, pending.action) end
  local pagers_ok=adapt14_pagers(find,transform,w)
  local board_ok=transform('art642.select.board',0,0,1)
  local cardsOk=true
  for _,name in ipairs(ADAPT715R_SELECT_CARDS) do
    cardsOk=transform(name,0,0,cardScale) and cardsOk
  end
  -- 撕边组已重挂到art641.select末尾；显隐逐叶处理，不依赖父级级联。
  -- 746（P2-1）：仅当子节点数达到该组预期叶数 v.expect 时才写入缓存 tearKids；未齐组每 0.25s 单独复查，已齐组零重枚举。
  st.tearKids=st.tearKids or {}; st.tearState=st.tearState or {}
  local tears_complete746=true
  for _,v in ipairs(ADAPT715R_TEARS) do
    local group=find(v.name)
    if group then
      local gok=set_visible(group,selecting)
      local kids=st.tearKids[v.name]
      local expect_n=v.expect or 1
      local group_complete=(kids~=nil)
      if not group_complete then
        local good,children=pcall(e744_get_kids,group)
        if good and type(children)=='table' and #children>0 then
          kids=children
          if #children>=expect_n then
            st.tearKids[v.name]=kids
            group_complete=true
          end
        end
      end
      if not group_complete then tears_complete746=false end
      if force or (not group_complete) or st.tearState[v.name]~=selecting then
        if selecting then pcall(e744_last_sib,group) end
        local done=gok
        if kids then
          for i=1,#kids do done=set_visible(kids[i],selecting) and done end
        else
          done=false
        end
        if done and group_complete then
          st.tearState[v.name]=selecting
        else
          st.tearState[v.name]=nil
        end
      end
    else
      tears_complete746=false
    end
    local tok=transform(v.name,adapt14_corner(w,h,v.side))
    if not tok then tears_complete746=false end
  end`
);

patch(
  'P1-3与P2-1_steady_ok745严格纳入翻页与撕边完整就绪',
  `  local tears_done745=true
  for _,v in ipairs(ADAPT715R_TEARS) do
    if st.tearState[v.name]~=selecting then tears_done745=false; break end
  end
  st.steady_ok745=(visible==true and missing==0 and failed==0 and cardsOk==true and wax_ok==true and st.leafState==bgWanted and tears_done745)`,
  `  local tears_done745=tears_complete746
  if tears_done745 then
    for _,v in ipairs(ADAPT715R_TEARS) do
      if st.tearState[v.name]~=selecting then tears_done745=false; break end
    end
  end
  -- 746（P1-3 & P2-1）：翻页 4 控件定位、board 定位、全部撕边组预期叶数与显隐全部确认就绪才进入 steady 早退。
  st.steady_ok745=(visible==true and missing==0 and failed==0 and cardsOk==true and wax_ok==true and pagers_ok==true and board_ok==true and st.leafState==bgWanted and tears_done745)`
);

// ── 8. P2-2：sync_econ742 写入后回读位置/缩放/显隐，全部命中目标值才缓存 steady ──
patch(
  'P2-2_sync_econ742写后回读确认到位再缓存',
  `  -- 保持中心锚定：上部按键自然内收，下部按钮也有等量余地。
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
  end`,
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
  local ok_e, verified = pcall(apply_and_verify_econ746, group, scale, active)
  if ok_e and verified == true then
    st.applied_sig=signature; st.applied_group=group
    if st.signature~=signature then
      st.signature=signature
      print('[econ742] '..signature)
    end
  else
    st.applied_sig=nil; st.applied_group=nil
  end`
);

// ── 8b. 加固 clear_board_portraits 在旧句柄销毁场景下的 pcall 保护 ──────────
patch(
  '加固_render_impl的clear_board_portraits保护',
  `      if adapter and adapter.clear_board_portraits then adapter:clear_board_portraits() end`,
  `      if adapter and adapter.clear_board_portraits then pcall(adapter.clear_board_portraits, adapter) end`
);

// ── 8c. Bonus-3：非关内切屏跳过 _apply_baked 中缺失的 fart.case_xxx 扫描 + same_value 支持嵌套表判等 ──
patch(
  'Bonus-3_same_value支持嵌套表值比较避免每帧重复下发与查找',
  `local function same_value(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if b[k] ~= v then return false end end
  for k, v in pairs(b) do if a[k] ~= v then return false end end
  return true
end`,
  `local function same_value(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do
    local bv = b[k]
    if bv ~= v then
      if type(v) ~= "table" or type(bv) ~= "table" or not same_value(v, bv) then return false end
    end
  end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end`
);

patch(
  'Bonus-3_非关内跳过apply_baked的缺失fart扫描',
  `function Adapter:_apply_baked(want_log)
  local want = self._baked_level or false
  local levels = (self.cfg and self.cfg.baked_levels) or { "case_001", "case_002" }
  local root = self:find("root")
  self._baked_state = self._baked_state or {}
  for i = 1, #levels do
    local lv = levels[i]
    local box = self:find("fart." .. lv)`,
  `function Adapter:_apply_baked(want_log)
  local want = self._baked_level or false
  local levels = (self.cfg and self.cfg.baked_levels) or { "case_001", "case_002" }
  self._baked_state = self._baked_state or {}
  -- 746：非关内（want == false）且先前从未找到/显示过对应烘焙盒时，跳过缺失的 fart.* 查找与 root:GetChildren 兜底，
  -- 彻底消除同关切屏时因 fart.case_001 缺项触发的 8,578 节点全树索引重建！
  if want == false then
    local any_known = false
    for i = 1, #levels do
      local lv = levels[i]
      local st = self._baked_state[lv]
      if st == nil or st.found or st.show or self.controls["fart." .. lv] ~= nil then
        any_known = true
        break
      end
    end
    if not any_known then return true end
  end
  local root = self:find("root")
  for i = 1, #levels do
    local lv = levels[i]
    local box = self:find("fart." .. lv)`
);

// ── 8d. Bonus-4：同关切屏保留已隐藏且非关内的 _misses 退避（非关内切屏不再清掉 cell.* 等已知缺项退避），避免每次切屏重扫全树 ──
patch(
  'Bonus-4_同关切屏精准清miss避免非关内cell缺项触发全树重建',
  `      else
        -- 树未重建：清掉未命中节流以便新页迟到控件立即重查，保留全部有效句柄，0 全树 DFS / 0 全树射线重扫！
        adapter._misses = nil
        adapter._miss_streak = nil
        adapter._mark_layer_dirty745 = true
      end`,
  `      else
        -- 746：树未重建时，仅清掉与当前目标页相关的未命中节流；非关内切屏保留 cell.* 缺项退避，
        -- 避免首页/选关/商店/背包互切时因 cell.1.2 缺项触发 8,578 节点全树索引重建；进关时完整清零。
        if self.screen == nil or self.screen == "level" then
          adapter._misses = nil
          adapter._miss_streak = nil
        elseif adapter._misses ~= nil then
          for mk in pairs(adapter._misses) do
            if type(mk) ~= "string" or mk:sub(1, 5) ~= "cell." then
              adapter._misses[mk] = nil
              if adapter._miss_streak ~= nil then adapter._miss_streak[mk] = nil end
            end
          end
        end
        adapter._mark_layer_dirty745 = true
      end`
);

// ── 9. 版本标记更新为 v746 ────────────────────────────────────────────────
patch(
  '版本标记1',
  `if print then print("[murdoku] ===== 构建标记 v745 / 解禁全面优化 =====") end`,
  `if print then print("[murdoku] ===== 构建标记 v746 / 评审加固与切屏消峰 =====") end`
);

patch(
  '版本标记2',
  `print("[murdoku] ===== 构建标记 v745 / 解禁全面优化 =====")`,
  `print("[murdoku] ===== 构建标记 v746 / 评审加固与切屏消峰 =====")`
);

// ── 语法检查 + shop_cold_render 回归检查 ───────────────────────────────────
fs.mkdirSync(temp, { recursive: true });
const candPath = path.join(temp, 'candidate746.lua');
fs.writeFileSync(candPath, lua, 'utf8');

const syn = spawnSync('lua', ['-e', `assert(loadfile(${JSON.stringify(candPath)})); print("SYNTAX PASS")`], { encoding: 'utf8' });
assert.equal(syn.status, 0, 'Lua 语法检查失败:\n' + syn.stderr);
process.stdout.write(syn.stdout);

function runCold(scriptText) {
  const r = spawnSync('lua', [path.join(repo, 'tests/shop_cold_render.lua')], { input: scriptText, encoding: 'utf8' });
  assert.equal(r.status, 0, 'shop_cold_render 失败:\n' + r.stderr);
  const m = r.stdout.match(/COLD=(\d+) WRITES=(\d+) COLD_FINDS=(\d+) FINDS=(\d+)/);
  assert(m, '未匹配到 COLD 输出: ' + r.stdout);
  return m.slice(1).map(Number);
}
const coldBefore = runCold(original);
const coldAfter = runCold(lua);
console.log('COLD 745', coldBefore, '746', coldAfter);
// same_value 深度判等会消除同页面重复 render 时的嵌套表无效重发（WRITES 应 <= 745，COLD/COLD_FINDS/FINDS 不超过 745）
assert.equal(coldAfter[0], coldBefore[0], 'COLD 应与 745 一致');
assert(coldAfter[1] <= coldBefore[1], 'WRITES 不应高于 745');
assert.equal(coldAfter[2], coldBefore[2], 'COLD_FINDS 应与 745 一致');
assert(coldAfter[3] <= coldBefore[3], 'FINDS 不应高于 745');

const candSha = sha(Buffer.from(lua, 'utf8'));
if (isCandidate) {
  console.log('CANDIDATE OK', candPath, 'patches=', patches.length, 'sha256=', candSha);
  process.exit(0);
}

// ── 正式产出：必须已有匹配的独立验证报告 ────────────────────────────────────
const validationArg = process.argv.find((a) => a.startsWith('--validation='));
const validationPath = validationArg
  ? path.resolve(validationArg.slice(13))
  : path.join(temp, 'validation746.json');
assert(fs.existsSync(validationPath), '缺少独立验证结果文件：' + validationPath);
const validationFile = JSON.parse(fs.readFileSync(validationPath, 'utf8'));
const validation = validationFile.validation || validationFile;
assert.equal(validation.candidateSha256, candSha, '独立验证对象 SHA256 与当前候选不一致');
assert.equal(validation.pass, true, '独立验证未通过');

leaf.field.payload = Buffer.from(lua, 'utf8');
leaf.field.len = leaf.field.payload.length;
leaf.field.sub = null;

fs.mkdirSync(path.dirname(out), { recursive: true });
const recordBytes = new Map(g.recs.map((r) => [r.id, encodeMsg([r.field])]));
const report = writeGil(g, out, {
  label: '746 评审加固与切屏消峰',
  expectDiffs: 1,
  expectMarker: 'v746',
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
fs.writeFileSync(path.join(outDir, '746_内嵌脚本.lua'), lua, 'utf8');
const summary = {
  baseVersion: '745',
  baseSha256: sha(g.src),
  baseBytes: g.src.length,
  scriptBytesBefore: Buffer.byteLength(original, 'utf8'),
  scriptBytesAfter: Buffer.byteLength(lua, 'utf8'),
  candidateSha256: candSha,
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
    '同一套桩与同一口径下统一横向对比 743 / 744 / 745 / 746，并同时报告暂停自动 GC 的累计堆分配增量与逐帧 P50/P95/P99/Max',
    '746 以 tools/build_746.mjs 与 746_内嵌脚本.lua 为派生链，0 控件记录改动',
  ],
};
fs.writeFileSync(path.join(outDir, '746_性能与验证.json'), JSON.stringify(summary, null, 2), 'utf8');
console.log('OUTPUT', out, report.bytes, sha(report.g2.src));
