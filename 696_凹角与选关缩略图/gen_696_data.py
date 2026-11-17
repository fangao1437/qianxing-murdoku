"""696 · 数据/补丁规格生成（基于 695 最小增量）

用户 2026-11-15 22:38 反馈：
  1. 695 真机三格地毯已渲染，但 L 形「凹侧顶点」处外框断开，要补上边缘缺口。
  2. 选关页面：每张卡片的棕色区域加「棋盘缩略图」（只要棋盘底色 + 门墙，家具省略）；
     下方白色边缘加关卡名。

A 凹角缺口：L3a/L3b 各 3 个 108×108 格位 × 3 圈，凹角顶点在 216×216 画布中心 (0,0)。
  右上格下边 / 左下格右边的深棕外框各占 12.96 宽，但两条带在角点只以一点相接，
  中间露出深色底/墙 ⇒ 视觉缺口。各补 1 层 12.96×12.96 的深棕角片到缺角象限的
  左上角（L3a (6.48,-6.48)，L3b (-6.48,-6.48)），源/母本 content 各一份 ⇒ 4 条新记录，
  两个 content 的 childList 9→10。

B 选关缩略图：全部在 Lua 侧完成，零静态文本改动、零谜题改动。
  · Levels.ui_list() 增 walls / doors / room_grid（逐格房间号）
  · Controller:push_room_thumb 重写：棕色 inner 区域画 rows×cols 格底色 + 墙（深墨细条）
    + 门（铜金短条），不画家具；旧 6 个 room 大色块收起
  · 卡片底部白色边缘的 .info 文本改为关卡短名、style=card.name（深棕字）；
    顶部 .title 改为规格信息
  · Adapter:color_of_style 增 card.name → 深棕
"""
import json, pathlib, copy, hashlib, sys
sys.stdout.reconfigure(encoding='utf-8')
ROOT = pathlib.Path(__file__).resolve().parent
P695 = ROOT.parent / '695_地毯原型注册与改名'
LUA695 = (P695 / '695_内嵌Lua_695.lua').read_bytes().decode('utf8')
SPEC695 = json.loads((P695 / '695_设计与补丁.json').read_text(encoding='utf8'))
K695 = json.loads((P695 / '695_关卡数据.json').read_text(encoding='utf8'))
FURN695 = json.loads((P695 / '695_家具规格.json').read_text(encoding='utf8'))


def func_span(src, header):
    i = src.index(header)
    j = src.index('\nend\n', i) + len('\nend\n')
    return i, j, src[i:j]


# ── P1 Levels.ui_list：补 walls / doors / room_grid ────────────────────
i1, j1, UI_OLD = func_span(LUA695, 'function M.ui_list()')
UI_NEW = '''function M.ui_list()
  local out = {}
  local list = M.all()
  for i = 1, #list do
    local lv = list[i]
    local sz = lv.size
    local rows = type(sz) == "table" and tonumber(sz.rows) or nil
    local cols = type(sz) == "table" and tonumber(sz.cols) or nil
    local room_grid = nil
    if rows and cols then
      local ok, grid = pcall(function()
        return RoomMap.compute_rooms(rows, cols, RoomMap.build_walls(lv, rows, cols))
      end)
      if ok then room_grid = grid end
    end
    out[i] = {
      id = lv.id, name = lv.name, difficulty = lv.difficulty,
      size = lv.size, suspects = lv.suspects, victim = lv.victim,
      rooms = lv.rooms, objects = lv.objects,
      room_boxes = RoomMap.boxes(lv),
      room_names = lv.room_names,
      -- 696：选关卡片棋盘缩略图用（底色 + 门墙，家具省略）
      walls = lv.walls, doors = lv.doors, room_grid = room_grid,
    }
  end
  return out
end
'''

# ── P2 Controller:push_room_thumb：重写为棋盘缩略图 ───────────────────
i2, j2, THUMB_OLD = func_span(LUA695, 'function Controller:push_room_thumb(')
THUMB_NEW = '''function Controller:push_room_thumb(push, cardId, it, cardRect, parent)
  -- 696：选关卡片棕色区域 = 棋盘缩略图（每格房间底色 + 墙 + 门），家具省略。
  -- 关卡名由 build_layout 的 .info 节点放在下方白色边缘。
  local area = { x = cardRect.x + cardRect.w * 0.069,
                 y = cardRect.y + cardRect.h * 0.164,
                 w = cardRect.w * 0.861, h = cardRect.h * 0.783 }
  local sz = it and it.size or nil
  local rows = type(sz) == "table" and tonumber(sz.rows) or nil
  local cols = type(sz) == "table" and tonumber(sz.cols) or nil
  local grid = it and it.room_grid or nil
  local walls = it and it.walls or nil
  local doors = it and it.doors or nil
  -- 旧版 6 个房间大色块全部收起，避免与缩略图叠色
  for j = 1, ROOM_MAX do
    push({ id = cardId .. ".room." .. j, kind = "button", parent = parent,
           visible = false, rect = { x = area.x, y = area.y, w = 1, h = 1 },
           pos_runtime = true })
  end
  if not rows or not cols or rows < 1 or cols < 1 then return end
  local pad = 8
  local gx, gy = area.x + pad, area.y + pad
  local gw, gh = area.w - pad * 2, area.h - pad * 2
  local cw, ch = gw / cols, gh / rows
  -- ① 每格底色（按房间编号取 ROOM_COLORS），不画任何家具
  for r = 1, rows do
    for c = 1, cols do
      local rn = (type(grid) == "table" and type(grid[r]) == "table")
                 and tonumber(grid[r][c]) or nil
      local tint = Controller.room_color(rn) or Controller.ROOM_COLORS[((r + c) % #Controller.ROOM_COLORS) + 1]
      push({ id = cardId .. ".cell." .. r .. "." .. c, kind = "button", parent = parent,
             visible = true,
             rect = { x = gx + (c - 1) * cw + 0.5, y = gy + (r - 1) * ch + 0.5,
                      w = math.max(1, cw - 1), h = math.max(1, ch - 1) },
             image = WHITE_MAT, tint = tint, pos_runtime = true })
    end
  end
  -- ② 墙（深墨细条）与门（铜金短条，只占格线中段 44%）
  local INK  = { r = 32, g = 38, b = 44 }
  local GOLD = { r = 220, g = 91, b = 41 }
  local function seg(kind, r, c)
    if kind == "v" then
      return gx + c * cw - 1, gy + (r - 1) * ch, 2, ch
    end
    return gx + (c - 1) * cw, gy + r * ch - 1, cw, 2
  end
  local function line(suffix, x, y, w, h, tint)
    push({ id = cardId .. suffix, kind = "button", parent = parent, visible = true,
           rect = { x = x, y = y, w = math.max(1, w), h = math.max(1, h) },
           image = WHITE_MAT, tint = tint, pos_runtime = true })
  end
  local k = 0
  for n = 1, (type(walls) == "table" and #walls or 0) do
    local w = walls[n]
    if type(w) == "table" and (w[1] == "v" or w[1] == "h") then
      k = k + 1
      local x, y, ww, hh = seg(w[1], tonumber(w[2]) or 0, tonumber(w[3]) or 0)
      line(".wall." .. k, x, y, ww, hh, INK)
    end
  end
  local d = 0
  for n = 1, (type(doors) == "table" and #doors or 0) do
    local o = doors[n]
    if type(o) == "table" and (o[1] == "v" or o[1] == "h") then
      d = d + 1
      local x, y, ww, hh = seg(o[1], tonumber(o[2]) or 0, tonumber(o[3]) or 0)
      if o[1] == "v" then
        line(".door." .. d, x - 1, y + hh * 0.28, 4, hh * 0.44, GOLD)
      else
        line(".door." .. d, x + ww * 0.28, y - 1, ww * 0.44, 4, GOLD)
      end
    end
  end
end
'''

# ── P3 卡片文本：底部白边放关卡短名（深棕字），顶部放规格信息 ─────────
a3 = LUA695.index('          local t = self:level_card_parts(it)')
b3 = LUA695.index('          self:push_room_thumb(push, "select.card." .. i, it, r, "select")', a3)
CARD_OLD = LUA695[a3:b3]
CARD_NEW = CARD_OLD.replace(
    'visible = true, text = t.title, style = "card.title",',
    'visible = true, text = t.info, style = "card.title",').replace(
    'visible = true, text = t.info, style = "muted",',
    'visible = true, text = t.short, style = "card.name",')
assert CARD_NEW != CARD_OLD and 'text = t.short, style = "card.name"' in CARD_NEW, 'P3 卡片文本替换失败'

# ── P4 level_card_parts：增加 short（去掉「案件 NNN · 」前缀） ──────────
PART_OLD = '  return { title = title, info = table.concat(bits, "　"), result = result }'
PART_NEW = ('  local short = string.match(title, "^案件%s*%d+%s*·%s*([^·]+)")\n'
            '             or string.match(title, "·%s*(.+)$") or title\n'
            '  short = string.gsub(short, "%s+$", "")\n'
            '  return { title = title, short = short, info = table.concat(bits, "　"), result = result }')
assert LUA695.count(PART_OLD) == 1, 'P4 锚点不唯一'

# ── P5 color_of_style：card.name → 深棕 ────────────────────────────────
STYLE_OLD = '  if value == "clue.who" then return RED end'
STYLE_NEW = ('  if value == "card.name" then return 0xFF4A2E1C end   -- 696：白纸边缘的关卡名用深棕\n'
             '  if value == "clue.who" then return RED end')
assert LUA695.count(STYLE_OLD) == 1, 'P5 锚点不唯一'

PATCHES = [
    dict(name='P1 ui_list 补 walls/doors/room_grid', old=UI_OLD, new=UI_NEW),
    dict(name='P2 push_room_thumb 重写为棋盘缩略图', old=THUMB_OLD, new=THUMB_NEW),
    dict(name='P3 卡片底部白边放关卡名、顶部放规格', old=CARD_OLD, new=CARD_NEW),
    dict(name='P4 level_card_parts 增 short', old=PART_OLD, new=PART_NEW),
    dict(name='P5 color_of_style 增 card.name 深棕', old=STYLE_OLD, new=STYLE_NEW),
]
s = LUA695
for p in PATCHES:
    assert s.count(p['old']) == 1, '锚点不唯一/缺失：' + p['name']
    s = s.replace(p['old'], p['new'], 1)
back = s
for p in reversed(PATCHES):
    back = back.replace(p['new'], p['old'], 1)
assert back == LUA695, 'Lua 补丁无法反向逐字节还原 695'
LUA696 = s
(ROOT / '696_内嵌Lua_696.lua').write_bytes(LUA696.encode('utf8'))

# ── 凹角补片规格 ──────────────────────────────────────────────────────
CORNER = dict(
    color='0xFFB89A62', imageId=100001, size=12.96,
    note='深棕外框色，与每格「深色底」层同色；放在 L 形缺角象限的左上角，'
         '把右上格下边 / 左下格右边的两条外框带连成连续 L 形直角',
    patches=[
        dict(content=1073760714, cloneFrom=1073760716, x=6.48, y=-6.48, template='furn.rug.4', copy='src'),
        dict(content=1073760715, cloneFrom=1073760719, x=6.48, y=-6.48, template='furn.rug.4', copy='mama'),
        dict(content=1073760737, cloneFrom=1073760739, x=-6.48, y=-6.48, template='furn.rug.5', copy='src'),
        dict(content=1073760738, cloneFrom=1073760742, x=-6.48, y=-6.48, template='furn.rug.5', copy='mama'),
    ],
)

# ── 输出规格与数据 ────────────────────────────────────────────────────
SPEC696 = copy.deepcopy(SPEC695)
SPEC696['version'] = 696
SPEC696['base'] = dict(file='../695_地毯原型注册与改名/695_地毯原型注册与改名.gil',
                       luaBytes=len(LUA695.encode('utf8')),
                       sha256Lua=hashlib.sha256(LUA695.encode('utf8')).hexdigest())
SPEC696['rootCause'] = dict(
    summary='695 真机三格地毯已渲染；本轮补 L 形凹角顶点的外框缺口 + 选关卡片棋盘缩略图',
    evidence=['真机截图：L 形外框在凹角顶点仅以一点相接，中间露出深色底/墙色',
              '两套素材 3 格位 × 3 圈，凹角顶点 (0,0) 没有任何层覆盖缺角象限的角点'],
    fix='R1 两套素材源/母本 content 各补 1 层深棕角片；B1~B5 选关缩略图 Lua 补丁',
)
SPEC696['luaPatches'] = PATCHES
SPEC696['cornerPatch'] = CORNER
SPEC696['selectThumb'] = dict(
    area='棕色 inner 比例 x+6.9% / y+16.4% / w86.1% / h78.3%，内缩 8px',
    cells='rows×cols 格，每格按 room_grid 房间号取 ROOM_COLORS 底色',
    walls='深墨 #20262C 细条；v=列间竖线，h=行间横线',
    doors='橙红 #DC5B29 短条，占格线中段 44%',
    furniture='不画（用户要求省略）',
    name='底部白色边缘 .info 文本 = 关卡短名，style=card.name 深棕 #4A2E1C',
    info='顶部 .title = 6x6 / 嫌疑人数等规格信息',
)
FURN696 = copy.deepcopy(FURN695)
for tpl, x in [('furn.rug.4', 6.48), ('furn.rug.5', -6.48)]:
    a = FURN696['newAssets'][tpl]
    assert a['layerCount'] == 9
    a['layers'].append(dict(part='凹角封口', quad='缺角象限左上角', x=x, y=-6.48,
                            w=CORNER['size'], h=CORNER['size'], imageId=CORNER['imageId'],
                            color=CORNER['color'], order=10,
                            note='696：源/母本 content 各一份，共 2 条记录；闭合 L 形外框的凹侧顶点'))
    a['layerCount'] = 10
    a['cornerPatch'] = CORNER['note']
(ROOT / '696_设计与补丁.json').write_bytes(json.dumps(SPEC696, ensure_ascii=False, indent=2).encode('utf8'))
(ROOT / '696_关卡数据.json').write_bytes(json.dumps(K695, ensure_ascii=False, indent=2).encode('utf8'))
(ROOT / '696_家具规格.json').write_bytes(json.dumps(FURN696, ensure_ascii=False, indent=2).encode('utf8'))
(ROOT / '696_静态文本补丁.json').write_bytes(json.dumps(
    dict(texts=[], note='696 静态文本零改动；关卡名走 Lua 动态文本节点'), ensure_ascii=False, indent=2).encode('utf8'))

# 顺序对照表沿用
order_md = (P695 / '695_顺序对照表.md').read_text(encoding='utf8').replace('695', '696')
(ROOT / '696_顺序对照表.md').write_bytes(order_md.encode('utf8'))

print('696 数据/补丁规格生成完成')
print('  695 Lua 字节', len(LUA695.encode('utf8')), '→ 696', len(LUA696.encode('utf8')))
print('  Lua 补丁', len(PATCHES), '项；凹角补片', len(CORNER['patches']), '条新记录')
print('  反向还原 695：逐字节一致 ✓')
