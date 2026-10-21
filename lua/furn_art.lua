--[[----------------------------------------------------------------------------
  lua/furn_art.lua —— 第一二关的「家具美术」数据与分组（v300，2026-10-22 第二轮）

  为什么要这个模块（用户 2026-10-22 打回第一版的判词）：
    ① **复刻效果不佳**：第一版每件家具只有 3 层、全靠矩形/圆叠，像"色块图解"，不像原作那种
       带深色描边的平面图标；
    ② **跨格家具不许拆成两格**：第一关的桌子占 (1,1)+(2,1)、第二关占 (1,2)+(1,3)，
       第一版按格各画一份 ⇒ 屏幕上像"两张小桌子"而不是一张长桌。

  本轮的做法（不动格子模板之外的结构）：
    · **每格 6 层**（模板里的 `obj`/`obj2`/…/`obj6`）⇒ 一件家具最多用 6 个官方基础形状叠出来：
      L1 深色外形（等价于原作的黑色描边）→ L2 主体 → L3 内面 → L4..L6 细节（木纹/靠背/扶手/书本…）；
    · **跨格家具合并成一件**：按 `object` 键把 4 邻接的同种格子做**连通分组**，
      整件美术**只画在锚点格（组的右下格，见 `anchor_of`）**，元素坐标以「整件包围盒中心」为原点，
      允许 `w/h > 1`、`dx/dy` 超过 ±0.5 —— 越过格子边界由锚点格整体绘制（脚本会把它抬到最上层，
      见适配层 `furn_anchor`），因此屏幕上**是一整件**，且会压住两格之间的格线（原作也是对象压墙线）；
    · **地毯**平铺且可站人（人/笔记要压在它上面）⇒ 地毯**不溢出**：按整块地毯的包围盒
      逐格"切矩形"（外框 + 内面），所以多格地毯看起来是一整块、没有格线，但仍在各自格子里；
    · **房间名标签**：`labels` 容器里的 7 个文本框由界面层按房间外框摆位（见 `F.room_boxes`）。

  配色（就近换算自原作 `puzzle-24h-delivery-easy` 的暖色房屋系；原作双色见
  `murdoku-project/美术实现-一二关-2026-10-22/原作美术参考-2026-10-22.md`）：
    描边/深色 #6B5B45 · 木面 #C9A96E · 浅木面 #DCC08C · 奶白 #EFE5C8 · 靠背 #DFD2AE
    地毯外框 #B89A62 · 地毯内面 #DCC684 · 叶 #5E9E4A / 暗叶 #3E6E36 · 陶盆 #8A5A3A / 盆暗 #5A3A26

  坐标单位一律 = **格子**（格边长 = 1），y **向下**为正。
----------------------------------------------------------------------------]]--

local F = {}

F.MAX_LAYERS = 6

-- ══════════════════════════════════════════════════════════════════════════
-- 调色板（0xAARRGGBB；与白色底板素材【乘算】）
-- ══════════════════════════════════════════════════════════════════════════
local C = {
  ink      = 0xFF6B5B45,   -- 深棕：本色当"描边"
  ink_dark = 0xFF4A3E2E,   -- 更深的缝/层板
  wood     = 0xFFC9A96E,   -- 木面
  wood_lt  = 0xFFDCC08C,   -- 浅木面
  wood_hi  = 0xFFE8D2A4,   -- 高光木
  cream    = 0xFFEFE5C8,   -- 奶白（坐垫/床单）
  cream_lt = 0xFFF7EFD8,   -- 更亮奶白
  tan      = 0xFFDFD2AE,   -- 浅棕（靠背）
  tan_dk   = 0xFFC6B183,   -- 深一档的棕（坐垫/扶手，用来和奶白主体拉开明度）
  rug_rim  = 0xFFB89A62,   -- 地毯外框
  rug_in   = 0xFFDCC684,   -- 地毯内面
  rug_mid  = 0xFFC9B072,   -- 地毯内框线（中间调）
  rug_hi   = 0xFFEBD9A8,   -- 地毯高光条
  pot      = 0xFF8A5A3A,   -- 陶盆
  pot_dk   = 0xFF5A3A26,   -- 陶盆暗
  leaf     = 0xFF5E9E4A,   -- 叶
  leaf_dk  = 0xFF3E6E36,   -- 叶暗
  leaf_hi  = 0xFF8FCF74,   -- 叶高光
  stone    = 0xFF8E8E9A,   -- 石座
  stone_dk = 0xFF4E4E56,   -- 石座暗
  stone_db = 0xFF7A7A86,   -- 石座压边（暗一档）
  bust     = 0xFFC9C9D2,   -- 雕塑主体
  bust_hi  = 0xFFE2E2E8,   -- 雕塑高光
  book1    = 0xFF8A6A48,
  book2    = 0xFFA08050,
  book3    = 0xFF6E8A9A,
}

-- 官方素材 id 速查（详见 murdoku-project/美术实现-一二关-2026-10-22/README.md §2.2）
--
--   ★ 2026-10-22 第二轮按 `_work/art-slot/零件词表-v2.md`（asset-hunt 逐张实测）换过一轮：
--     106xxx 的圆角矩形**四角半径不一致、带撕裂/缺口**（106046 底边 1.7% 缺口、106045 四角 r≈0~2.4），
--     真正"边缘干净"的圆角矩形在 107xxx；所以主体/台面改用 107102 / 107002，阴影用 106056。
local IMG = {
  rect   = 100001,   -- 基础形状·矩形（纯白 256²，直角；线/条/书脊都用它拉）
  circle = 100002,   -- 基础形状·圆形（纯白 256²）
  ring   = 100006,   -- 基础形状·圆环（线宽≈6.9%，当"描边圈"）
  plate  = 100001,   -- 底板-彩色·近白方板 96×96（四角 r≈6，RGB254，边缘干净）
  panel  = 100001,   -- 底板-彩色·近白圆角板 336×256（四角 r≈12，自带一圈细边=缝线）
  grain  = 107088,   -- 底板-彩色·横木纹条 660×68（深棕；低透明度叠在桌面上当木纹）
  soft   = 106056,   -- 底板-单色·柔光圆 96²（白心向外渐隐；染深=柔和投影）
  urn    = 105090,   -- 装饰图案·奶白瓮 176×112（近白可染）
}

-- ══════════════════════════════════════════════════════════════════════════
-- 美术：kind → 变体（按"长边格数"分；`[1]` = 单格，`[2]` = 跨两格，长轴 = X）
--
--   每个元素：{ id, color, w, h, dx, dy }   —— 单位 = 格子，dx 右 / dy 下为正
--   数组顺序 = **从下往上** 的层序（第 i 个元素落到第 i 层 `obj`…`obj6`）。
--   `[2]` 变体只按"长轴 = X"画；实际是竖着的（包围盒高 > 宽）时由 `orient_els` 交换 dx/dy 与 w/h。
-- ══════════════════════════════════════════════════════════════════════════
F.ART = {
  -- 椅子（俯视扶手椅）：深色外形 + 奶白主体 + **更深的坐垫** + 靠背条 + **两条竖扶手**
  --
  --  ★ 2026-10-22 第二轮第二版（art-preview 独立校验的反馈）：第一版坐垫与主体同色（奶白×奶白），
  --    整件叠成一个"圆角托盘/枕头"，两条 0.10 宽的扶手被身体颜色吃掉。
  --    这一版：坐垫改 tan（与奶白主体拉开明度）、扶手加宽到 0.12 且**贴到身体内侧边缘**、
  --    靠背条压在上沿 ⇒ 俯视时能读出"上沿靠背 + 左右扶手 + 中间坐垫"的扶手椅结构。
  chair = {
    [1] = {
      { id = IMG.plate,  color = C.ink,      w = 0.90, h = 0.92, dy =  0.02 },
      { id = IMG.plate,  color = C.cream,    w = 0.82, h = 0.84, dy =  0.02 },
      { id = IMG.plate,  color = C.tan_dk,   w = 0.54, h = 0.46, dy =  0.13 },
      { id = IMG.rect,   color = C.cream_lt, w = 0.62, h = 0.12, dy = -0.29 },
      { id = IMG.rect,   color = C.tan_dk,   w = 0.13, h = 0.52, dx = -0.345, dy =  0.03 },
      { id = IMG.rect,   color = C.tan_dk,   w = 0.13, h = 0.52, dx =  0.345, dy =  0.03 },
    },
  },

  -- 桌子（俯视桌/餐桌）：单格 = 方桌；两格 = 长桌（**一整件**，不是两张）
  table = {
    [1] = {
      { id = IMG.soft,   color = 0x40000000, w = 1.00, h = 0.98, dy =  0.06 },
      { id = IMG.plate,  color = C.ink,      w = 0.90, h = 0.86 },
      { id = IMG.plate,  color = C.wood,     w = 0.82, h = 0.78 },
      { id = IMG.plate,  color = C.wood_lt,  w = 0.66, h = 0.60 },
      { id = IMG.rect,   color = C.ink,      w = 0.56, h = 0.02, dy = -0.12 },
      { id = IMG.rect,   color = C.ink,      w = 0.56, h = 0.02, dy =  0.12 },
    },
    [2] = {
      { id = IMG.soft,   color = 0x40000000, w = 2.00, h = 0.98, dy =  0.06 },
      { id = IMG.plate,  color = C.ink,      w = 1.90, h = 0.86 },
      { id = IMG.plate,  color = C.wood,     w = 1.82, h = 0.78 },
      { id = IMG.plate,  color = C.wood_lt,  w = 1.66, h = 0.58 },
      { id = IMG.rect,   color = C.ink,      w = 1.50, h = 0.02, dy = -0.13 },
      { id = IMG.rect,   color = C.ink,      w = 1.50, h = 0.02, dy =  0.13 },
    },
  },

  -- 植物（盆栽）：柔和投影 + 陶盆 + 叶簇 + 高光
  plant = {
    [1] = {
      { id = IMG.soft,   color = 0x42000000, w = 0.92, h = 0.92, dy =  0.14 },
      { id = IMG.plate,  color = C.pot_dk,   w = 0.48, h = 0.38, dy =  0.25 },
      { id = IMG.plate,  color = C.pot,      w = 0.40, h = 0.30, dy =  0.26 },
      { id = IMG.circle, color = C.leaf_dk,  w = 0.70, h = 0.58, dy = -0.10 },
      { id = IMG.circle, color = C.leaf,     w = 0.58, h = 0.46, dy = -0.08 },
      { id = IMG.circle, color = C.leaf_hi,  w = 0.26, h = 0.20, dx = -0.10, dy = -0.18 },
    },
  },

  -- 书架/柜：**粗黑外框（原作特征，5%/边）** + 木柜体 + 两条层板 + 两组书脊
  shelf = {
    [1] = {
      { id = IMG.rect,   color = C.ink,      w = 0.90, h = 0.80 },
      { id = IMG.rect,   color = C.wood,     w = 0.80, h = 0.70 },
      { id = IMG.rect,   color = C.ink_dark, w = 0.70, h = 0.05, dy = -0.12 },
      { id = IMG.rect,   color = C.ink_dark, w = 0.70, h = 0.05, dy =  0.12 },
      { id = IMG.rect,   color = C.book1,    w = 0.14, h = 0.16, dx = -0.19, dy =  0.00 },
      { id = IMG.rect,   color = C.book3,    w = 0.14, h = 0.16, dx =  0.15, dy =  0.00 },
    },
  },

  -- 雕塑：柔和投影 + 石座（两级）+ **肩 + 头（两个圆）** —— 读成"台座上的半身像"
  --
  --  ★ 2026-10-22 第二轮第二版（art-preview 反馈"像台灯/棋子"）：第一版是"柱子 + 一个圆头"，
  --    这一版把"肩"（宽扁圆）和"头"（小圆）分开，并把石座做成两级台阶 ⇒ 半身像的体块出来了。
  statue = {
    [1] = {
      { id = IMG.soft,   color = 0x4A000000, w = 0.86, h = 0.86, dy =  0.20 },
      { id = IMG.rect,   color = C.stone_dk, w = 0.58, h = 0.22, dy =  0.32 },
      { id = IMG.rect,   color = C.stone,    w = 0.50, h = 0.13, dy =  0.26 },
      { id = IMG.circle, color = C.bust,     w = 0.40, h = 0.28, dy = -0.01 },
      { id = IMG.circle, color = C.bust_hi,  w = 0.22, h = 0.20, dy = -0.19 },
      { id = IMG.rect,   color = C.stone,    w = 0.30, h = 0.035, dy =  0.16 },
    },
  },
}

-- ══════════════════════════════════════════════════════════════════════════
-- 地毯：**按整块地毯的包围盒逐格切矩形**（不溢出格子，所以可站人、笔记压得住）
--
--   元素语义：外框（整块地毯底色）+ 内面（向内缩 0.10 格）+ 高光条（仅当该格在整块的第一行）
--   ⇒ 组内相邻格之间没有"每格一条边"，看起来是**一整块**。
-- ══════════════════════════════════════════════════════════════════════════
F.RUG_INSET = 0.12   -- 内面相对包围盒内缩（格）
F.RUG_LINE  = 0.20   -- 内框线再往里缩（格）

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- 区间 [a,b]（格坐标，格 i 占 [i-0.5, i+0.5]）与格 i 的交集，返回相对格中心的比例宽度与偏移
local function slice_axis(a, b, i)
  local lo = math.max(a, i - 0.5)
  local hi = math.min(b, i + 0.5)
  if hi <= lo then return nil, nil end
  local w = hi - lo
  local center = (lo + hi) * 0.5
  return w, center - i
end

-- 生成某块地毯在某一格上的元素（按整块包围盒切矩形 ⇒ 组内无"每格一条边"）
--
--   ★ 2026-10-22 第二版：去掉"只在首行出现的一条高光"（第一版看起来像一条压边胶带），
--     改成**三层矩形**：外框（深）→ 内面（浅）→ 内框线（中）——
--     每层都是"整块矩形与该格的交集"，所以多格地毯拼起来就是**一整块带双线边框的地毯**，
--     而且外框贴满整格、格线会在它上面透出来（原作的地毯上就压着全局网格线）。
function F.rug_cell_els(bbox, r, c)
  local els = {}
  local function slice_rect(inset, color)
    local xa, xb = bbox.c1 - 0.5 + inset, bbox.c2 + 0.5 - inset
    local ya, yb = bbox.r1 - 0.5 + inset, bbox.r2 + 0.5 - inset
    local w, dx = slice_axis(xa, xb, c)
    local h, dy = slice_axis(ya, yb, r)
    if w == nil or h == nil then return nil end
    -- 各方向多铺 0.02 格：与邻格同色重叠，接缝不露白
    return { id = IMG.rect, color = color, w = w + 0.04, h = h + 0.04, dx = dx, dy = dy }
  end
  -- ① 外框（贴满整格）
  els[#els + 1] = { id = IMG.rect, color = C.rug_rim, w = 1.0, h = 1.0 }
  -- ② 内面
  local inner = slice_rect(F.RUG_INSET, C.rug_in)
  if inner ~= nil then els[#els + 1] = inner end
  -- ③ 内框线（再往里一圈、用中间色 ⇒ 地毯有"双层边"的层次）
  local line = slice_rect(F.RUG_LINE, C.rug_mid)
  if line ~= nil then els[#els + 1] = line end
  return els
end

-- ══════════════════════════════════════════════════════════════════════════
-- 分组 / 摆位
-- ══════════════════════════════════════════════════════════════════════════

-- ══════════════════════════════════════════════════════════════════════════
-- 分组规则：**哪些家具会合并成"一件"**
--
--   ★ 这里踩过一次（2026-10-22 第一版预览就露馅）：
--     一开始"相邻同种就合并"，结果第二关的**两盆植物 (5,4)+(6,4)** 被并成一件
--     ⇒ 花盆被转了 90°、还只剩一盆。
--   ⇒ 只有"本来就该跨格"的家具才合并：
--       · `table`  —— 长桌（第一关竖两格、第二关横两格）
--       · `carpet` —— 地毯（按整块切矩形，视觉连续）
--     其它（chair / plant / shelf / statue）**一格一件**，相邻也各画各的。
-- ══════════════════════════════════════════════════════════════════════════
local COMBINE = { table = true, carpet = true }

-- 锚点格：整件美术画在这一格里（取组的**右下格**：行最大、行相同取列最大）
local function anchor_of(bbox)
  return { r = bbox.r2, c = bbox.c2 }
end

-- 房间名标签落在哪一格：**优先"最后一行里没有家具的格"**（字压在空地上才清楚），
-- 其次房间最后一行任意格，再不行就取房间中心。
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

-- 把"以整件包围盒中心为原点"的元素换算成"以锚点格中心为原点"
--   bbox 中心（格坐标）= ((c1+c2)/2, (r1+r2)/2)；锚点格中心 = (c2, r2)
local function to_anchor(els, bbox, anchor, vertical)
  local out = {}
  local bcx = (bbox.c1 + bbox.c2) * 0.5
  local bcy = (bbox.r1 + bbox.r2) * 0.5
  for i = 1, #els do
    local e = els[i]
    local x, y = e.dx or 0, e.dy or 0
    local w, h = e.w or 1, e.h or 1
    if vertical then
      -- 长轴在 Y：把"长轴=X"的美术转 90°（只交换轴，不旋转控件）
      x, y = y, x
      w, h = h, w
      -- 交换后，原 dx 是沿长轴的偏移 ⇒ 现在应沿 y；用交换后的 x,y 即可
    end
    out[#out + 1] = {
      id = e.id,
      color = e.color,
      w = w,
      h = h,
      dx = (bcx + x) - anchor.c,
      dy = (bcy + y) - anchor.r,
    }
  end
  return out
end

-- 取变体：有对应长边格数的就用它，否则退回单格
function F.variant(kind, span)
  local set = F.ART[kind]
  if type(set) ~= "table" then return nil end
  return set[span] or set[1]
end

--[[
  layout(vm, keys, room_names) -> {
      cell  = { [r] = { [c] = { els = <数组或false>, anchor = bool } } },
      boxes = { [room] = { r1=,r2=,c1=,c2=, n= } },
      labels = { { room=, text=, box= } ... }
  }
  `keys[r][c]` = 该格的 `obj.<kind>` 字符串或 false（界面层已用 `Controller.object_key_of` 算好）
  `room_names` = 关卡数据里的数组（真名）或 nil（显示"区域N"）
]]
function F.layout(vm, keys, room_names)
  local res = { cell = {}, boxes = {}, labels = {} }
  if vm == nil or vm.cells == nil then return res end
  local rows, cols = vm.rows or 0, vm.cols or 0
  for r = 1, rows do
    res.cell[r] = {}
    for c = 1, cols do res.cell[r][c] = { els = false, anchor = false } end
  end

  -- ── ① 分组：**只有 COMBINE 里的种类才做 4 邻接合并**，其余一格一件 ──────────
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
          -- BFS：相邻同 key 视为同一件
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
          -- 一格一件（两盆相邻的植物是**两盆**，不是一件两格家具）
          seen[r .. ":" .. c] = true
          group[1] = { r, c }
        end
        pieces[#pieces + 1] = {
          key = key,
          kind = kind,
          cells = group,
          box = { r1 = r1, r2 = r2, c1 = c1, c2 = c2 },
          occupiable = nil,
        }
      end
    end
  end

  -- ── ② 逐件分配美术 ────────────────────────────────────────────────────
  for _, p in ipairs(pieces) do
    local b = p.box
    local kind = p.kind
    local span_r, span_c = b.r2 - b.r1 + 1, b.c2 - b.c1 + 1
    local span = math.max(span_r, span_c)
    local vertical = span_r > span_c
    if kind == "carpet" then
      -- 地毯：逐格切（不溢出、可站人）
      for _, cell in ipairs(p.cells) do
        res.cell[cell[1]][cell[2]].els = F.rug_cell_els(b, cell[1], cell[2])
      end
    else
      local els = F.variant(kind, span)
      if els ~= nil then
        local anchor = anchor_of(b)
        local local_els = to_anchor(els, b, anchor, vertical)
        local info = res.cell[anchor.r][anchor.c]
        info.els = local_els
        info.anchor = (span_r > 1 or span_c > 1)   -- 只有跨格才需要抬层
      end
    end
  end

  -- ── ③ 房间外框（给"房间名标签"摆位用）────────────────────────────────
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
      cell = pick_label_cell(box, keys),   -- 标签落在哪一格（见下）
    }
  end

  return res
end

return F
