--[[----------------------------------------------------------------------------
  lua/furn_art.lua —— 第一二关的「家具美术」数据与分组（v301，2026-10-22 第三轮）

  三轮的来龙去脉（用户判词一次比一次具体）：
    · 第一轮（v299）：每件家具 3 层基础形状 ⇒ 用户：「复刻效果不佳，与原作差距过大，
      至少要达到参考图的水准；跨格家具不许拆成两格」；
    · 第二轮（v300）：6 层 + 跨格整件 + 房间名 ⇒ 用户：「重新参考原作的桌子和椅子、书架、植物，
      详细的参考它们的细节，先把你抓到的参考给我」⇒ 交出四张参考图后用户确认：
        「底板参考先暂时保留素材，不做修改，植物减少一些叶片可以，其它家具的细节保留（包括阴影，
          横桌竖桌明显需要分开做）图层3是肯定不够了，你可以任意添加」
    · 第三轮（v301，本文件）：**按原作的部件表逐件照搭**，层数上限给到 **12 层**（`obj`…`obj12`），
      横放长桌 / 竖放长桌**各做一套**（不再靠交换坐标轴），阴影全部保留。

  原作的实测依据（`_work/art-ref/家具几何分解.md` + `_work/art-ref/review/refB|refC-*.png`）：
    · 每件 = base 白剪影 + overlay 白剪影，两层分别乘关卡两色；明暗来自 base 内部灰阶（不是第三层）；
    · 黑描边是素材里的**黑色填充块**：桌 ≈2.5% 格、书架 **5%**、植物 1~1.5%；
    · **椅子没有黑描边**（轮廓是 overlay 线画层，棕金色）；
    · 桌子**没有 overlay**；俯视略前倾 ⇒ 看得见**下沿深灰桌沿 + 端部两个腿头**，中段无腿；
    · 书架是**正面立面**画法：粗黑框 + 内凹黑框 + 2 道隔板 + 一排竖书脊（书脊 = overlay 青）；
    · 植物是**俯视放射**：8~10 片尖叶（每片黑叶缘）+ 上宽下窄盆 + 盆沿高光 + 盆底投影。

  结构不变的部分（第二轮已经定稿、本轮不改）：
    · **跨格家具合并成一件**：按 `object` 键 4 邻接分组（只有 table/carpet 参与合并），
      整件只画在**锚点格（右下格）**，元素允许越出格子（适配层把它 `SetAsLastSibling` 抬到最上层）；
    · **地毯按整块包围盒逐格切矩形**（可站人、视觉连续）；
    · **房间名标签**按房间外框摆位（优先没有家具的格）；
    · 底板/地板**沿用现有素材，不改**（用户明确：底板参考先暂时保留素材）。

  坐标单位一律 = **格子**（格边长 = 1），`dx` 右为正、`dy` **下**为正；颜色 `0xAARRGGBB` 与白色底板**乘算**。
----------------------------------------------------------------------------]]--

local F = {}

-- 模板里每格的家具层数（`obj` … `obj12`），由 `tools/gil/gen_art_containers.mjs` 的 v2 版生成
F.MAX_LAYERS = 12

-- ══════════════════════════════════════════════════════════════════════════
-- 调色板：**直接用原作实测的颜色**（24h-delivery / House Party 关的 obj_color）
--   原作两色机制的对应关系：base 色 = 主体、overlay 色 = 第二色部件、灰阶暗部 = 本色×灰阶。
-- ══════════════════════════════════════════════════════════════════════════
local C = {
  -- 黑描边（原作是素材里的黑色填充块，不是 stroke）
  ink      = 0xFF1F1A14,
  ink_soft = 0xFF3A322A,
  -- 桌子：base #e0ce7b / 深一档 #ad9c67（原作不画 overlay，这一档当桌沿/暗部）
  table    = 0xFFAD9C67,   -- 原作图标实测像素 #AD9C67（不是 #E0CE7B，那是关卡 base 色）
  table_dk = 0xFF8C7F52,   -- 桌沿：比桌面深一档
  table_hi = 0xFFEFE3A0,
  leg      = 0xFFA08F5C,   -- 桌腿   -- 腿头（比桌面深一档，才看得出来）
  -- 椅子：base #fef7e4 / overlay #fbd592
  chair    = 0xFFFEF7E4,
  chair_dk = 0xFFE9D9B2,   -- base×灰阶（靠背内区/扶手）
  chair_hi = 0xFFFBF2DA,   -- 前缘亮面
  chair_ov = 0xFFFBD592,   -- overlay（靠背顶带）
  chair_ln = 0xFFD9C08A,   -- 原作 overlay 线画的平均色（当"棕金描边"）
  -- 书架：base #d0b0d9 / overlay #b2dbeb
  shelf    = 0xFFD0B0D9,
  shelf_hi = 0xFFE4CBE9,   -- 顶板 / 隔板
  shelf_ln = 0xFFB49CC0,   -- 柜体暗缝
  book_a   = 0xFFB2DBEB,   -- overlay 书脊
  book_b   = 0xFF9CCFE6,
  book_c   = 0xFFC7E7F2,
  -- 植物：盆 base #fca161 / 叶 overlay #79cfa1
  pot      = 0xFFFCA161,
  pot_hi   = 0xFFFFB782,
  pot_dk   = 0xFFD97F3F,
  leaf     = 0xFF79CFA1,
  leaf_dk  = 0xFF5FB884,
  leaf_hi  = 0xFFA8E6C4,
  leaf_ink = 0xFF1E2A18,   -- 原作黑叶缘（1~1.5% 格）
  -- 雕塑：base #ffffff / overlay #c0c0c0（The Secret Lab 的蓝灰石色）
  stone    = 0xFFC9C9D2,
  stone_hi = 0xFFE2E2E8,
  stone_dk = 0xFF8E8E9A,
  stone_ink= 0xFF3E3E48,
  -- 地毯：只用 overlay #fee08e，外圈是固有深色 #39484d × overlay
  rug_rim  = 0xFFB89A62,
  rug_in   = 0xFFDCC684,
  rug_mid  = 0xFFC9B072,
  -- 通用
  shadow   = 0x9A000000,   -- 柔和投影（乘在 106056 白心柔光圆上；桌子加了"下偏移"，需比原来实一点）
}

-- 官方素材 id 速查（白模；换色靠 imageColor 乘算）
local IMG = {
  rect   = 100001,   -- 基础形状·矩形（纯白 256²，直角、可任意拉伸）
  circle = 100002,   -- 基础形状·圆形（纯白 256²；拉伸成椭圆=叶/肩）
  plate  = 100001,   -- 直角矩形（层板/分隔线/腿）
  round  = 107102,   -- 近白圆角方板 96²（r≈6、边缘干净；106053 四边中点有手绘缺口，拉长后像"咬边"）
  soft   = 106056,   -- 柔光圆 96²（白心向外渐隐 ⇒ 染深色=柔和投影）
}

-- ══════════════════════════════════════════════════════════════════════════
-- 美术数据：`F.ART[kind][variant] = { 从下往上的元素数组 }`
--
--   variant：
--     "1"  = 单格
--     "h2" = **横放**两格长桌（长轴 = X，宽 ≈1.9 格）
--     "v2" = **竖放**两格长桌（长轴 = Y，高 ≈1.9 格）—— 用户明确要求横竖分开做
--   元素：{ id, color, w, h, dx, dy }，单位 = 格；dx 右、dy 下为正。
--   ⚠️ 每个 kind 的元素数 ≤ F.MAX_LAYERS(12)；超出部分会被适配层静默截掉。
-- ══════════════════════════════════════════════════════════════════════════
F.ART = {
  -- ── 桌子（照原作图标再加工：圆角外形 / 桌面 / 底部黑分隔线 / 深色桌沿 / 两条带黑边的腿）──
  --   ★ 2026-10-22 第五轮：用户「桌子略显粗糙，进一步照原作加工」。
  --   原作图标的俯视构成（实测 bbox 396×455，竖长 0.87）：
  --     · 桌面占高度 ~81%，四角小圆角、外圈黑描边 ≈2.5%/边
  --     · 下面一条**黑色分隔线**，再往下一条**深色桌沿**（灰阶乘 base ⇒ 深橄榄）
  --     · 最下面**两条腿**（各带黑边，腿比桌沿更靠内）
  --   尺寸按原作比例：单格长边 0.836 格 ⇒ 宽 0.73 / 高 0.836；两格长桌长边 1.75 格。
  table = {
    -- 单格方桌：整件 bbox = 0.73 × 0.836 格（= 原作"长边占格 0.836、宽高比 0.87"）
    ["1"] = {
      { id = IMG.soft,  color = C.shadow,   w = 0.73, h = 0.96, dy =  0.22 },   -- ① 投影（往下偏，从桌沿/腿下方露出）
      { id = IMG.round, color = C.ink,      w = 0.730, h = 0.700, dy = -0.068 }, -- ② 黑描边（圆角）
      { id = IMG.round, color = C.table,    w = 0.680, h = 0.650, dy = -0.068 }, -- ③ 桌面
      { id = IMG.rect,  color = C.ink,      w = 0.680, h = 0.028, dy =  0.272 }, -- ④ 黑分隔线
      { id = IMG.rect,  color = C.table_dk, w = 0.680, h = 0.055, dy =  0.309 }, -- ⑤ 桌沿（深色）
      { id = IMG.rect,  color = C.ink,      w = 0.680, h = 0.022, dy =  0.348 }, -- ⑥ 桌沿下黑线
      { id = IMG.rect,  color = C.ink,      w = 0.070, h = 0.070, dx = -0.235, dy = 0.375 }, -- ⑦ 左腿黑边
      { id = IMG.rect,  color = C.leg,      w = 0.046, h = 0.046, dx = -0.235, dy = 0.375 }, -- ⑧ 左腿
      { id = IMG.rect,  color = C.ink,      w = 0.070, h = 0.070, dx =  0.235, dy = 0.375 }, -- ⑨ 右腿黑边
      { id = IMG.rect,  color = C.leg,      w = 0.046, h = 0.046, dx =  0.235, dy = 0.375 }, -- ⑩ 右腿
    },
    -- 横放两格：长轴 = X，长边 = 1.672 格（= 2×0.836），宽 0.73 格；桌沿沿长边、腿在两端
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
    -- 竖放两格：**单独一套**，长轴 = Y，长边 1.672、宽 0.73；桌沿/腿在底边
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

  -- ── 椅子（照原作 8 部件：主体 / 靠背内区 / 靠背顶带 / 坐垫 / 前缘 / 两扶手 + 棕金轮廓）──
  chair = {
    ["1"] = {
      { id = IMG.soft,   color = C.shadow,   w = 0.92, h = 0.92, dy =  0.10 },   -- ① 投影
      { id = IMG.rect,   color = C.chair_ln, w = 0.90, h = 0.92, dy =  0.02 },   -- ② 棕金轮廓（原作 overlay 线画的近似）
      { id = IMG.rect,   color = C.chair,    w = 0.82, h = 0.84, dy =  0.02 },   -- ③ 主体剪影
      { id = IMG.rect,   color = C.chair_dk, w = 0.58, h = 0.26, dy = -0.24 },   -- ④ 靠背内区
      { id = IMG.rect,   color = C.chair_ov, w = 0.64, h = 0.14, dy = -0.32 },   -- ⑤ 靠背顶带（overlay 色）
      { id = IMG.rect,   color = C.chair,    w = 0.48, h = 0.30, dy =  0.10 },   -- ⑥ 坐垫（比内区亮）
      { id = IMG.rect,   color = C.chair_hi, w = 0.68, h = 0.12, dy =  0.35 },   -- ⑦ 前缘亮面
      { id = IMG.rect,   color = C.chair_dk, w = 0.12, h = 0.34, dx = -0.33, dy = 0.03 }, -- ⑧ 左扶手
      { id = IMG.rect,   color = C.chair_dk, w = 0.12, h = 0.34, dx =  0.33, dy = 0.03 }, -- ⑨ 右扶手
    },
  },

  -- ── 书架（照原作 7 部件：粗黑外框 / 顶板 / 柜体 / 内凹黑框 / 两道隔板 / 一排书脊 + 底影）──
  shelf = {
    ["1"] = {
      { id = IMG.soft,   color = C.shadow,   w = 0.90, h = 0.50, dy =  0.42 },   -- ① 底部投影
      { id = IMG.rect,   color = C.ink,      w = 0.92, h = 0.86 },               -- ② 粗黑外框（≈5%/边）
      { id = IMG.rect,   color = C.shelf,    w = 0.82, h = 0.76, dy = -0.01 },   -- ③ 柜体
      { id = IMG.rect,   color = C.shelf_hi, w = 0.80, h = 0.10, dy = -0.35 },   -- ④ 顶板
      { id = IMG.rect,   color = C.ink,      w = 0.70, h = 0.56, dy = -0.01 },   -- ⑤ 内凹黑框
      { id = IMG.rect,   color = C.shelf_hi, w = 0.72, h = 0.06, dy = -0.06 },   -- ⑥ 隔板 1
      { id = IMG.rect,   color = C.shelf_hi, w = 0.72, h = 0.06, dy =  0.24 },   -- ⑦ 隔板 2
      { id = IMG.rect,   color = C.book_a,   w = 0.08, h = 0.20, dx = -0.26, dy = -0.20 }, -- ⑧ 书脊 1（上层）
      { id = IMG.rect,   color = C.book_b,   w = 0.08, h = 0.15, dx = -0.16, dy = -0.18 }, -- ⑨ 书脊 2
      { id = IMG.rect,   color = C.book_c,   w = 0.08, h = 0.18, dx = -0.06, dy = -0.19 }, -- ⑩ 书脊 3
      { id = IMG.rect,   color = C.book_a,   w = 0.08, h = 0.14, dx = -0.22, dy =  0.06 }, -- ⑪ 书脊 4（下层）
      { id = IMG.rect,   color = C.book_b,   w = 0.08, h = 0.17, dx = -0.12, dy =  0.05 }, -- ⑫ 书脊 5（下层）
    },
  },

  -- ── 植物（照原作俯视放射：每片叶"黑叶缘垫底 + 叶本色"成对，共 4 片 + 盆沿/盆身/盆底暗 + 投影）──
  --   ★ 用户已同意"减少一些叶片"（原作 8~10 片）；每片叶要 2 层（黑边+叶）⇒ 4 片刚好 12 层用满。
  plant = {
    ["1"] = {
      { id = IMG.soft,   color = C.shadow,   w = 0.94, h = 0.94, dy =  0.18 },   -- ① 投影
      { id = IMG.circle, color = C.leaf_ink, w = 0.15, h = 0.50, dx = -0.24, dy = -0.06 }, -- ② 叶 L 黑边
      { id = IMG.circle, color = C.leaf,     w = 0.10, h = 0.44, dx = -0.24, dy = -0.07 }, -- ③ 叶 L
      { id = IMG.circle, color = C.leaf_ink, w = 0.15, h = 0.48, dx =  0.24, dy = -0.05 }, -- ④ 叶 R 黑边
      { id = IMG.circle, color = C.leaf,     w = 0.10, h = 0.42, dx =  0.24, dy = -0.06 }, -- ⑤ 叶 R
      { id = IMG.circle, color = C.leaf_ink, w = 0.15, h = 0.52, dx = -0.05, dy = -0.14 }, -- ⑥ 叶 M1 黑边
      { id = IMG.circle, color = C.leaf,     w = 0.10, h = 0.46, dx = -0.05, dy = -0.15 }, -- ⑦ 叶 M1
      { id = IMG.circle, color = C.leaf_ink, w = 0.14, h = 0.44, dx =  0.12, dy = -0.09 }, -- ⑧ 叶 M2 黑边
      { id = IMG.circle, color = C.leaf_hi,  w = 0.08, h = 0.36, dx =  0.12, dy = -0.10 }, -- ⑨ 叶 M2（亮）
      { id = IMG.rect,   color = C.pot_hi,   w = 0.46, h = 0.10, dy =  0.13 },   -- ⑩ 盆沿
      { id = IMG.rect,   color = C.pot,      w = 0.36, h = 0.24, dy =  0.25 },   -- ⑪ 盆身
      { id = IMG.rect,   color = C.pot_dk,   w = 0.36, h = 0.06, dy =  0.35 },   -- ⑫ 盆底暗
    },
  },

  -- ── 雕塑（原作 8 部件：投影 / 两级台座 / 台柱 / 肩 / 头 / 高光 / 台座线）──
  statue = {
    ["1"] = {
      { id = IMG.soft,   color = C.shadow,   w = 0.86, h = 0.86, dy =  0.20 },   -- ① 投影
      { id = IMG.rect,   color = C.stone_ink,w = 0.64, h = 0.16, dy =  0.40 },   -- ② 台座底（黑边）
      { id = IMG.rect,   color = C.stone_dk,w = 0.58, h = 0.12, dy =  0.38 },   -- ③ 台座底
      { id = IMG.rect,   color = C.stone_dk,w = 0.46, h = 0.10, dy =  0.28 },   -- ④ 台座上层
      { id = IMG.rect,   color = C.stone,   w = 0.24, h = 0.18, dy =  0.16 },   -- ⑤ 台柱
      { id = IMG.circle, color = C.stone,   w = 0.40, h = 0.26, dy = -0.02 },   -- ⑥ 肩
      { id = IMG.circle, color = C.stone_hi, w = 0.22, h = 0.20, dy = -0.20 },  -- ⑦ 头
      { id = IMG.circle, color = C.stone_hi, w = 0.10, h = 0.08, dx = -0.04, dy = -0.24 }, -- ⑧ 头高光
    },
  },
}

-- ══════════════════════════════════════════════════════════════════════════
-- 地毯：按整块包围盒逐格切矩形（外框 / 内面 / 内框线），可站人、视觉连续。
--   ⚠️ 用户 2026-10-22 第三轮：底板（地板）素材**不动**，所以地毯仍铺在现有格子色上。
-- ══════════════════════════════════════════════════════════════════════════
F.RUG_INSET = 0.12   -- 内面相对包围盒内缩（格）
F.RUG_LINE  = 0.20   -- 内框线再往里缩（格）

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

-- 生成某块地毯在某一格上的元素（三层矩形，都是"整块矩形 ∩ 本格"）
function F.rug_cell_els(bbox, r, c)
  local els = {}
  local function slice_rect(inset, color)
    local xa, xb = bbox.c1 - 0.5 + inset, bbox.c2 + 0.5 - inset
    local ya, yb = bbox.r1 - 0.5 + inset, bbox.r2 + 0.5 - inset
    local w, dx = slice_axis(xa, xb, c)
    local h, dy = slice_axis(ya, yb, r)
    if w == nil or h == nil then return nil end
    return { id = IMG.rect, color = color, w = w + 0.04, h = h + 0.04, dx = dx, dy = dy }
  end
  els[#els + 1] = { id = IMG.rect, color = C.rug_rim, w = 1.0, h = 1.0 }
  local inner = slice_rect(F.RUG_INSET, C.rug_in)
  if inner ~= nil then els[#els + 1] = inner end
  local line = slice_rect(F.RUG_LINE, C.rug_mid)
  if line ~= nil then els[#els + 1] = line end
  return els
end

-- ══════════════════════════════════════════════════════════════════════════
-- 分组 / 摆位
-- ══════════════════════════════════════════════════════════════════════════

-- 只有"本来就该跨格"的家具才合并；其它一格一件（两盆相邻的植物是两盆，不是一件）
local COMBINE = { table = true, carpet = true }

-- 锚点格：整件美术画在这一格里（组的**右下格**）
local function anchor_of(bbox)
  return { r = bbox.r2, c = bbox.c2 }
end

-- 房间名标签落在哪一格：优先"最后一行里没有家具的格"，其次房间最后一行任意空格，最后取房间中心
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

-- 取变体：单格 / 横放两格 / 竖放两格
--   ★ 2026-10-22 第三轮：**横桌竖桌各做一套**（用户明确要求），不再靠交换坐标轴；
--     只有"变体缺失"时才退回单格（不是几何错误，只是明显不对，用来在日志里被发现）。
function F.variant(kind, span_r, span_c)
  local set = F.ART[kind]
  if type(set) ~= "table" then return nil, nil end
  if span_r > 1 and span_c > 1 then
    -- L 形/方块：两个方向都跨 —— 本关没有；退回横放
    return set["h2"] or set["1"], "h2"
  elseif span_c > 1 then
    return set["h2"] or set["1"], "h2"
  elseif span_r > 1 then
    return set["v2"] or set["1"], "v2"
  end
  return set["1"], "1"
end

-- 把"以整件包围盒中心为原点"的元素换算成"以锚点格中心为原点"
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

--[[
  layout(vm, keys, room_names) -> {
      cell  = { [r] = { [c] = { els = <数组或false>, anchor = bool } } },
      boxes = { [room] = { r1,r2,c1,c2,n } },
      labels = { { room, text, box, cell } ... }
  }
  `keys[r][c]` = 该格的 `obj.<kind>` 字符串或 false（界面层用 `Controller.object_key_of` 算好）
]]
function F.layout(vm, keys, room_names)
  local res = { cell = {}, boxes = {}, labels = {} }
  if vm == nil or vm.cells == nil then return res end
  local rows, cols = vm.rows or 0, vm.cols or 0
  for r = 1, rows do
    res.cell[r] = {}
    for c = 1, cols do res.cell[r][c] = { els = false, anchor = false } end
  end

  -- ── ① 分组（只有 COMBINE 里的种类做 4 邻接合并）──────────────────────────
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

  -- ── ② 逐件分配美术 ────────────────────────────────────────────────────
  local chosen = {}
  for _, p in ipairs(pieces) do
    local b = p.box
    local kind = p.kind
    local span_r, span_c = b.r2 - b.r1 + 1, b.c2 - b.c1 + 1
    if kind == "carpet" then
      for _, cell in ipairs(p.cells) do
        res.cell[cell[1]][cell[2]].els = F.rug_cell_els(b, cell[1], cell[2])
      end
    else
      local els, variant = F.variant(kind, span_r, span_c)
      if els ~= nil then
        local anchor = anchor_of(b)
        local info = res.cell[anchor.r][anchor.c]
        info.els = to_anchor(els, b, anchor)
        info.anchor = (span_r > 1 or span_c > 1)
        chosen[#chosen + 1] = string.format("%s@%d,%d[%s]", kind, anchor.r, anchor.c, variant)
        -- ★ v302（第四轮）：界面层还要按"外部工具算出的图元拼法"给这些件生成 N 个图片控件，
        --   所以把 kind / 包围盒 / 锚点格 / 变体一起带出去（地毯由界面层自己跳过）。
        res.pieces = res.pieces or {}
        res.pieces[#res.pieces + 1] = {
          kind = kind, box = b, anchor = anchor, variant = variant,
          cells = p.cells, span_r = span_r, span_c = span_c,
        }
      end
    end
  end
  res.chosen = chosen   -- 给离线用例/预览核对"横竖是否各用各的变体"

  -- ── ③ 房间外框（给房间名标签摆位用）──────────────────────────────────
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
