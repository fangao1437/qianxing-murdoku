"""697 · 基于 696 最小增量

用户 2026-11-15 23:07 反馈：
  1. 「那个凸出来的小方块不要」——696 把 12.96² 深棕角片放在**缺角象限**的左上角，
     在 L 形凹角处形成了一个凸出到空白格的小方块。改为把角片**移到 L 形内侧的凹角顶点**：
     L3a（缺右下）→ (-6.48, 6.48)；L3b（缺左下）→ (6.48, 6.48)。
     这样两条深棕外框带仍在角点连成连续直角，但轮廓完全不凸出、不侵占缺角格。
  2. 「棋盘缩略图不用填满区域，保持正方形并居中即可」——把网格边长取
     min(area.w-16, area.h-16)，在棕色区域内居中；所有关卡 rows==cols，格子为正方形。

零新增/删除记录、零静态文本改动、零谜题改动。
"""
import json, pathlib, copy, hashlib, sys
sys.stdout.reconfigure(encoding='utf-8')
ROOT = pathlib.Path(__file__).resolve().parent
P696 = ROOT.parent / '696_凹角与选关缩略图'
LUA696 = (P696 / '696_内嵌Lua_696.lua').read_bytes().decode('utf8')
SPEC696 = json.loads((P696 / '696_设计与补丁.json').read_text(encoding='utf8'))
K696 = json.loads((P696 / '696_关卡数据.json').read_text(encoding='utf8'))
FURN696 = json.loads((P696 / '696_家具规格.json').read_text(encoding='utf8'))

# ── P1 缩略图：正方形 + 居中 ──────────────────────────────────────────
GRID_OLD = '''  local pad = 8
  local gx, gy = area.x + pad, area.y + pad
  local gw, gh = area.w - pad * 2, area.h - pad * 2
  local cw, ch = gw / cols, gh / rows'''
GRID_NEW = '''  -- 697：棋盘缩略图保持正方形并居中，不铺满棕色区域（四周留白）
  local pad = 8
  local gw, gh = area.w - pad * 2, area.h - pad * 2
  local side = math.min(gw, gh)
  local gx = area.x + (area.w - side) * 0.5
  local gy = area.y + (area.h - side) * 0.5
  local cw, ch = side / cols, side / rows'''
assert LUA696.count(GRID_OLD) == 1, 'P1 网格锚点不唯一'
LUA697 = LUA696.replace(GRID_OLD, GRID_NEW, 1)
assert LUA697.replace(GRID_NEW, GRID_OLD, 1) == LUA696, 'Lua 补丁无法反向逐字节还原 696'
(ROOT / '697_内嵌Lua_697.lua').write_bytes(LUA697.encode('utf8'))

# ── R1 角片内收：4 条记录只改几何中心 ────────────────────────────────
CORNER_MOVES = [
    dict(id=1073760757, template='furn.rug.4', copy='src',  old=(6.48, -6.48),  new=(-6.48, 6.48)),
    dict(id=1073760758, template='furn.rug.4', copy='mama', old=(6.48, -6.48),  new=(-6.48, 6.48)),
    dict(id=1073760759, template='furn.rug.5', copy='src',  old=(-6.48, -6.48), new=(6.48, 6.48)),
    dict(id=1073760760, template='furn.rug.5', copy='mama', old=(-6.48, -6.48), new=(6.48, 6.48)),
]

# ── 输出规格 ──────────────────────────────────────────────────────────
SPEC697 = copy.deepcopy(SPEC696)
SPEC697['version'] = 697
SPEC697['base'] = dict(file='../696_凹角与选关缩略图/696_凹角与选关缩略图.gil',
                       luaBytes=len(LUA696.encode('utf8')),
                       sha256Lua=hashlib.sha256(LUA696.encode('utf8')).hexdigest())
SPEC697['rootCause'] = dict(
    summary='696 的凹角补片凸出到缺角格；697 把 4 条角片内收到 L 形内侧凹角顶点，'
            '并把选关缩略图改成正方形居中',
    fix='R1 4 条角片几何中心内收；P1 网格边长取 min 并居中',
)
SPEC697['luaPatches'] = [dict(name='P1 棋盘缩略图正方形居中', old=GRID_OLD, new=GRID_NEW, count=1)]
SPEC697['cornerMoves'] = CORNER_MOVES
SPEC697['cornerPatch'] = copy.deepcopy(SPEC696.get('cornerPatch', {}))
SPEC697['cornerPatch']['note'] = (
    '697：角片从缺角象限移到 L 形内侧凹角顶点（L3a 左上格 / L3b 右上格），'
    '外框带仍连成连续直角，但轮廓不凸出、不侵占空白格')
SPEC697['selectThumb'] = copy.deepcopy(SPEC696['selectThumb'])
SPEC697['selectThumb']['area'] = ('棕色 inner 比例区域不变；网格边长 = min(区域宽-16, 区域高-16)，'
                                  '在区域内水平/垂直居中，四周留白')
SPEC697['selectThumb']['square'] = 'rows==cols ⇒ 每格正方形，整幅棋盘为正方形'
(ROOT / '697_设计与补丁.json').write_bytes(json.dumps(SPEC697, ensure_ascii=False, indent=2).encode('utf8'))

FURN697 = copy.deepcopy(FURN696)
for tpl, x in [('furn.rug.4', -6.48), ('furn.rug.5', 6.48)]:
    for L in FURN697['newAssets'][tpl]['layers']:
        if L.get('part') == '凹角封口':
            L['x'], L['y'] = x, 6.48
            L['quad'] = 'L 形内侧凹角顶点（不凸出）'
            L['note'] = '697：角片内收到 L 形内部，轮廓不再侵占缺角格'
(ROOT / '697_家具规格.json').write_bytes(json.dumps(FURN697, ensure_ascii=False, indent=2).encode('utf8'))
(ROOT / '697_关卡数据.json').write_bytes(json.dumps(K696, ensure_ascii=False, indent=2).encode('utf8'))
(ROOT / '697_静态文本补丁.json').write_bytes(json.dumps(
    dict(texts=[], note='697 静态文本零改动'), ensure_ascii=False, indent=2).encode('utf8'))
order_md = (P696 / '696_顺序对照表.md').read_text(encoding='utf8').replace('696', '697')
(ROOT / '697_顺序对照表.md').write_bytes(order_md.encode('utf8'))

print('697 数据/补丁规格生成完成')
print('  696 Lua 字节', len(LUA696.encode('utf8')), '→ 697', len(LUA697.encode('utf8')))
print('  角片内收', len(CORNER_MOVES), '条；Lua 补丁 1 项')
print('  反向还原 696：逐字节一致 ✓')
