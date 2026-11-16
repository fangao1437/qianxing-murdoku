local F = {}
F.MAX_LAYERS = 12
local C = {
  ink      = 0xFF1F1A14,
  ink_soft = 0xFF3A322A,
  table    = 0xFFAD9C67,    
  table_dk = 0xFF8C7F52,    
  table_hi = 0xFFEFE3A0,
  leg      = 0xFFA08F5C,    
  chair    = 0xFFFEF7E4,
  chair_dk = 0xFFE9D9B2,    
  chair_hi = 0xFFFBF2DA,    
  chair_ov = 0xFFFBD592,    
  chair_ln = 0xFFD9C08A,    
  shelf    = 0xFFD0B0D9,
  shelf_hi = 0xFFE4CBE9,    
  shelf_ln = 0xFFB49CC0,    
  book_a   = 0xFFB2DBEB,    
  book_b   = 0xFF9CCFE6,
  book_c   = 0xFFC7E7F2,
  pot      = 0xFFFCA161,
  pot_hi   = 0xFFFFB782,
  pot_dk   = 0xFFD97F3F,
  leaf     = 0xFF79CFA1,
  leaf_dk  = 0xFF5FB884,
  leaf_hi  = 0xFFA8E6C4,
  leaf_ink = 0xFF1E2A18,    
  stone    = 0xFFC9C9D2,
  stone_hi = 0xFFE2E2E8,
  stone_dk = 0xFF8E8E9A,
  stone_ink= 0xFF3E3E48,
  rug_rim  = 0xFFB89A62,
  rug_in   = 0xFFDCC684,
  rug_mid  = 0xFFC9B072,
  shadow   = 0x9A000000,    
}
local IMG = {
  rect   = 100001,    
  circle = 100002,    
  plate  = 100001,    
  round  = 107102,    
  soft   = 106056,    
}
F.ART = {
  table = {
    ["1"] = {
      { id = IMG.soft,  color = C.shadow,   w = 0.73, h = 0.96, dy =  0.22 },    
      { id = IMG.round, color = C.ink,      w = 0.730, h = 0.700, dy = -0.068 },  
      { id = IMG.round, color = C.table,    w = 0.680, h = 0.650, dy = -0.068 },  
      { id = IMG.rect,  color = C.ink,      w = 0.680, h = 0.028, dy =  0.272 },  
      { id = IMG.rect,  color = C.table_dk, w = 0.680, h = 0.055, dy =  0.309 },  
      { id = IMG.rect,  color = C.ink,      w = 0.680, h = 0.022, dy =  0.348 },  
      { id = IMG.rect,  color = C.ink,      w = 0.070, h = 0.070, dx = -0.235, dy = 0.375 },  
      { id = IMG.rect,  color = C.leg,      w = 0.046, h = 0.046, dx = -0.235, dy = 0.375 },  
      { id = IMG.rect,  color = C.ink,      w = 0.070, h = 0.070, dx =  0.235, dy = 0.375 },  
      { id = IMG.rect,  color = C.leg,      w = 0.046, h = 0.046, dx =  0.235, dy = 0.375 },  
    },
    ["h2"] = {
      { id = IMG.soft,  color = C.shadow,   w = 1.68, h = 1.10, dy =  0.26 },
      { id = IMG.round, color = C.ink,      w = 1.672, h = 0.700, dy = -0.068 },
      { id = IMG.round, color = C.table,    w = 1.622, h = 0.650, dy = -0.068 },
      { id = IMG.rect,  color = C.ink,      w = 1.622, h = 0.028, dy =  0.272 },
      { id = IMG.rect,  color = C.table_dk, w = 1.622, h = 0.055, dy =  0.309 },
      { id = IMG.rect,  color = C.ink,      w = 1.622, h = 0.022, dy =  0.348 },
      { id = IMG.rect,  color = C.ink,      w = 0.070, h = 0.070, dx = -0.600, dy = 0.375 },
      { id = IMG.rect,  color = C.leg,      w = 0.046, h = 0.046, dx = -0.600, dy = 0.375 },
      { id = IMG.rect,  color = C.ink,      w = 0.070, h = 0.070, dx =  0.600, dy = 0.375 },
      { id = IMG.rect,  color = C.leg,      w = 0.046, h = 0.046, dx =  0.600, dy = 0.375 },
    },
    ["v2"] = {
      { id = IMG.soft,  color = C.shadow,   w = 0.73, h = 1.76, dy =  0.22 },
      { id = IMG.round, color = C.ink,      w = 0.730, h = 1.672 },
      { id = IMG.round, color = C.table,    w = 0.680, h = 1.622 },
      { id = IMG.rect,  color = C.ink,      w = 0.680, h = 0.028, dy =  0.700 },
      { id = IMG.rect,  color = C.table_dk, w = 0.680, h = 0.055, dy =  0.737 },
      { id = IMG.rect,  color = C.ink,      w = 0.680, h = 0.022, dy =  0.776 },
      { id = IMG.rect,  color = C.ink,      w = 0.070, h = 0.070, dx = -0.235, dy = 0.800 },
      { id = IMG.rect,  color = C.leg,      w = 0.046, h = 0.046, dx = -0.235, dy = 0.800 },
      { id = IMG.rect,  color = C.ink,      w = 0.070, h = 0.070, dx =  0.235, dy = 0.800 },
      { id = IMG.rect,  color = C.leg,      w = 0.046, h = 0.046, dx =  0.235, dy = 0.800 },
    },
  },
  chair = {
    ["1"] = {
      { id = IMG.soft,   color = C.shadow,   w = 0.74, h = 0.80, dy =  0.06 },    
      { id = IMG.round,  color = C.chair_ln, w = 0.66, h = 0.74, dy =  0.00 },    
      { id = IMG.round,  color = C.chair,    w = 0.60, h = 0.68, dy =  0.00 },    
      { id = IMG.circle, color = C.chair_dk, w = 0.42, h = 0.22, dy = -0.21 },    
      { id = IMG.round,  color = C.chair_ov, w = 0.46, h = 0.11, dy = -0.29 },    
      { id = IMG.round,  color = C.chair_hi, w = 0.38, h = 0.20, dy =  0.09 },    
      { id = IMG.round,  color = C.chair_dk, w = 0.48, h = 0.10, dy =  0.29 },    
      { id = IMG.round,  color = C.chair_dk, w = 0.10, h = 0.26, dx = -0.27, dy = 0.00 },  
      { id = IMG.round,  color = C.chair_dk, w = 0.10, h = 0.26, dx =  0.27, dy = 0.00 },  
    },
  },
  shelf = {
    ["1"] = {
      { id = IMG.soft,   color = C.shadow,   w = 0.90, h = 0.50, dy =  0.42 },    
      { id = IMG.rect,   color = C.ink,      w = 0.92, h = 0.86 },                
      { id = IMG.rect,   color = C.shelf,    w = 0.82, h = 0.76, dy = -0.01 },    
      { id = IMG.rect,   color = C.shelf_hi, w = 0.80, h = 0.10, dy = -0.35 },    
      { id = IMG.rect,   color = C.ink,      w = 0.70, h = 0.56, dy = -0.01 },    
      { id = IMG.rect,   color = C.shelf_hi, w = 0.72, h = 0.06, dy = -0.06 },    
      { id = IMG.rect,   color = C.shelf_hi, w = 0.72, h = 0.06, dy =  0.24 },    
      { id = IMG.rect,   color = C.book_a,   w = 0.08, h = 0.20, dx = -0.26, dy = -0.20 },  
      { id = IMG.rect,   color = C.book_b,   w = 0.08, h = 0.15, dx = -0.16, dy = -0.18 },  
      { id = IMG.rect,   color = C.book_c,   w = 0.08, h = 0.18, dx = -0.06, dy = -0.19 },  
      { id = IMG.rect,   color = C.book_a,   w = 0.08, h = 0.14, dx = -0.22, dy =  0.06 },  
      { id = IMG.rect,   color = C.book_b,   w = 0.08, h = 0.17, dx = -0.12, dy =  0.05 },  
    },
  },
  plant = {
    ["1"] = {
      { id = IMG.soft,   color = C.shadow,   w = 0.56, h = 0.56, dy =  0.24 },    
      { id = IMG.circle, color = C.leaf_ink, w = 0.34, h = 0.24, dy = -0.04 },    
      { id = IMG.circle, color = C.leaf_ink, w = 0.12, h = 0.34, dx = -0.20, dy = -0.10 },  
      { id = IMG.circle, color = C.leaf,     w = 0.08, h = 0.28, dx = -0.20, dy = -0.11 },  
      { id = IMG.circle, color = C.leaf_ink, w = 0.12, h = 0.34, dx =  0.20, dy = -0.10 },  
      { id = IMG.circle, color = C.leaf,     w = 0.08, h = 0.28, dx =  0.20, dy = -0.11 },  
      { id = IMG.circle, color = C.leaf_ink, w = 0.13, h = 0.40, dx = -0.04, dy = -0.14 },  
      { id = IMG.circle, color = C.leaf_hi,  w = 0.09, h = 0.32, dx = -0.04, dy = -0.15 },  
      { id = IMG.rect,   color = C.pot_hi,   w = 0.40, h = 0.09, dy =  0.17 },    
      { id = IMG.rect,   color = C.pot,      w = 0.32, h = 0.22, dy =  0.29 },    
    },
  },
  statue = {
    ["1"] = {
      { id = IMG.soft,   color = C.shadow,   w = 0.62, h = 0.62, dy =  0.34 },    
      { id = IMG.rect,   color = C.stone_ink,w = 0.62, h = 0.14, dy =  0.42 },    
      { id = IMG.rect,   color = C.stone_dk,w = 0.56, h = 0.09, dy =  0.41 },     
      { id = IMG.rect,   color = C.stone_dk,w = 0.44, h = 0.09, dy =  0.30 },     
      { id = IMG.circle, color = C.stone,   w = 0.32, h = 0.44, dy =  0.03 },     
      { id = IMG.circle, color = C.stone_dk,w = 0.22, h = 0.36, dx =  0.05, dy = 0.04 },  
      { id = IMG.circle, color = C.stone,   w = 0.38, h = 0.20, dy = -0.06 },     
      { id = IMG.circle, color = C.stone_hi,w = 0.18, h = 0.16, dy = -0.23 },     
      { id = IMG.rect,   color = C.stone,   w = 0.12, h = 0.05, dy = -0.31 },     
      { id = IMG.rect,   color = C.stone_dk,w = 0.26, h = 0.10, dy =  0.18 },     
    },
  },
}
F.RUG_INSET = 0.12    
F.RUG_LINE  = 0.20    
local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end
local function slice_axis(a, b, i)
  local lo = math.max(a, i - 0.5)
  local hi = math.min(b, i + 0.5)
  if hi <= lo then return nil, nil end
  local w = hi - lo
  local center = (lo + hi) * 0.5
  return w, center - i
end
function F.rug_cell_els(bbox, r, c, cellset)
  local els = {}
  local function has(rr, cc) return cellset and cellset[rr] and cellset[rr][cc] end
  -- 与相邻地毯格共享的边「开放」，不内缩 ⇒ 内部不留格线；
  -- 其余边（含 L 形内凹的外围边）内缩 ⇒ 深色边框沿整块外围一圈。
  local openL, openR = has(r, c - 1), has(r, c + 1)
  local openU, openD = has(r - 1, c), has(r + 1, c)
  local function band(inset, color)
    local l  = c - 0.5 + (openL and 0 or inset)
    local rr = c + 0.5 - (openR and 0 or inset)
    local t  = r - 0.5 + (openU and 0 or inset)
    local b  = r + 0.5 - (openD and 0 or inset)
    return { id = IMG.rect, color = color,
             w = (rr - l) + 0.04, h = (b - t) + 0.04,
             dx = (l + rr) * 0.5 - c, dy = (t + b) * 0.5 - r }
  end
  els[#els + 1] = { id = IMG.rect, color = C.rug_rim, w = 1.0, h = 1.0 }
  els[#els + 1] = band(F.RUG_INSET, C.rug_in)
  els[#els + 1] = band(F.RUG_LINE, C.rug_mid)
  return els
end
local COMBINE = { table = true, carpet = true }
local function anchor_of(bbox)
  return { r = bbox.r2, c = bbox.c2 }
end
local function pick_label_cell(box, keys)
  for c = box.c1, box.c2 do
    if not (keys and keys[box.r2] and keys[box.r2][c]) then
      return { r = box.r2, c = c }
    end
  end
  for r = box.r2, box.r1, -1 do
    for c = box.c1, box.c2 do
      if not (keys and keys[r] and keys[r][c]) then
        return { r = r, c = c }
      end
    end
  end
  return { r = box.r2, c = box.c1 }
end
function F.variant(kind, span_r, span_c)
  local set = F.ART[kind]
  if type(set) ~= "table" then return nil, nil end
  if span_r > 1 and span_c > 1 then
    return set["h2"] or set["1"], "h2"
  elseif span_c > 1 then
    return set["h2"] or set["1"], "h2"
  elseif span_r > 1 then
    return set["v2"] or set["1"], "v2"
  end
  return set["1"], "1"
end
local function to_anchor(els, bbox, anchor)
  local out = {}
  local bcx = (bbox.c1 + bbox.c2) * 0.5
  local bcy = (bbox.r1 + bbox.r2) * 0.5
  for i = 1, #els do
    local e = els[i]
    out[#out + 1] = {
      id = e.id,
      color = e.color,
      w = e.w or 1,
      h = e.h or 1,
      dx = (bcx + (e.dx or 0)) - anchor.c,
      dy = (bcy + (e.dy or 0)) - anchor.r,
    }
  end
  return out
end
function F.layout(vm, keys, room_names)
  local res = { cell = {}, boxes = {}, labels = {} }
  if vm == nil or vm.cells == nil then return res end
  local rows, cols = vm.rows or 0, vm.cols or 0
  for r = 1, rows do
    res.cell[r] = {}
    for c = 1, cols do res.cell[r][c] = { els = false, anchor = false } end
  end
  local seen = {}
  local pieces = {}
  local dirs = { { 0, 1 }, { 1, 0 }, { 0, -1 }, { -1, 0 } }
  for r = 1, rows do
    for c = 1, cols do
      local key = keys and keys[r] and keys[r][c] or false
      if key and not seen[r .. ":" .. c] then
        local kind = key:match("^obj%.(.+)$") or key
        local group, r1, r2, c1, c2 = {}, r, r, c, c
        if COMBINE[kind] then
          local stack = { { r, c } }
          seen[r .. ":" .. c] = true
          while #stack > 0 do
            local p = table.remove(stack)
            group[#group + 1] = p
            if p[1] < r1 then r1 = p[1] end
            if p[1] > r2 then r2 = p[1] end
            if p[2] < c1 then c1 = p[2] end
            if p[2] > c2 then c2 = p[2] end
            for i = 1, #dirs do
              local nr, nc = p[1] + dirs[i][1], p[2] + dirs[i][2]
              if nr >= 1 and nr <= rows and nc >= 1 and nc <= cols
                and not seen[nr .. ":" .. nc]
                and keys and keys[nr] and keys[nr][nc] == key then
                seen[nr .. ":" .. nc] = true
                stack[#stack + 1] = { nr, nc }
              end
            end
          end
        else
          seen[r .. ":" .. c] = true
          group[1] = { r, c }
        end
        pieces[#pieces + 1] = {
          key = key, kind = kind, cells = group,
          box = { r1 = r1, r2 = r2, c1 = c1, c2 = c2 },
        }
      end
    end
  end
  local chosen = {}
  for _, p in ipairs(pieces) do
    local b = p.box
    local kind = p.kind
    local span_r, span_c = b.r2 - b.r1 + 1, b.c2 - b.c1 + 1
    if kind == "carpet" then
      local tri = nil
      if #p.cells == 3 and span_r == 2 and span_c == 2 then
        local has = {}
        for _, cell in ipairs(p.cells) do
          has[(cell[1] - b.r1) .. ":" .. (cell[2] - b.c1)] = true
        end
        if not has["1:1"] then tri = "L3a"           -- 缺右下：第3关
        elseif not has["1:0"] then tri = "L3b" end   -- 缺左下：第7关
      end
      -- 694：地毯只走整块模板（_spawn_whole_rug）。逐格手搭层全部关闭，
      -- 既避免与模板双绘，也不再出现「三张单格地毯拼接」的观感。
      res.pieces = res.pieces or {}
      res.pieces[#res.pieces + 1] = {
        kind = kind, box = b, anchor = anchor_of(b), variant = tri or "1",
        cells = p.cells, span_r = span_r, span_c = span_c,
      }
    else
      local els, variant = F.variant(kind, span_r, span_c)
      if els ~= nil then
        local anchor = anchor_of(b)
        local info = res.cell[anchor.r][anchor.c]
        info.els = to_anchor(els, b, anchor)
        info.anchor = (span_r > 1 or span_c > 1)
        chosen[#chosen + 1] = string.format("%s@%d,%d[%s]", kind, anchor.r, anchor.c, variant)
        res.pieces = res.pieces or {}
        res.pieces[#res.pieces + 1] = {
          kind = kind, box = b, anchor = anchor, variant = variant,
          cells = p.cells, span_r = span_r, span_c = span_c,
        }
      end
    end
  end
  res.chosen = chosen    
  for r = 1, rows do
    for c = 1, cols do
      local cd = vm.cells[r] and vm.cells[r][c]
      local room = cd and cd.room
      if type(room) == "number" then
        local box = res.boxes[room]
        if box == nil then
          box = { r1 = r, r2 = r, c1 = c, c2 = c, n = 0 }
          res.boxes[room] = box
        end
        if r < box.r1 then box.r1 = r end
        if r > box.r2 then box.r2 = r end
        if c < box.c1 then box.c1 = c end
        if c > box.c2 then box.c2 = c end
        box.n = box.n + 1
      end
    end
  end
  local rooms = {}
  for room in pairs(res.boxes) do rooms[#rooms + 1] = room end
  table.sort(rooms)
  for _, room in ipairs(rooms) do
    local box = res.boxes[room]
    local name = nil
    if type(room_names) == "table" then name = room_names[room] end
    if type(name) ~= "string" or name == "" then name = "区域 " .. tostring(room) end
    res.labels[#res.labels + 1] = {
      room = room, text = name, box = box,
      cell = pick_label_cell(box, keys),
    }
  end
  return res
end
return F
