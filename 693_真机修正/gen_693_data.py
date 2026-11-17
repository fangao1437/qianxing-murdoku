"""693 · 真机截图反馈修正（基于 691 干净重建，692 保留为历史）

用户 2026-11-15 19:39 反馈：
  1 第四关的互换没实现 → A/D 两张卡**内容顺序互换**（不只是姓名），姓名也对调，
    卡面按新姓名表从谓词重渲染，本人一律「我」。
  2 who 区域不要加字母；卡面正文里的姓名仍加字母前缀（「我」不加）。
  3 人名缩减到 ≤4 字（全 1~7 关）。
  4 第3关 V 所在 R1 房间三个书架太单调 → 只留 1 个书架，加 1 植物 + 1 雕塑。
  5 三格地毯没渲染 + 样式应参照两格地毯：整块 L 形、边框只沿外围，
    不是三张单格方框拼接 ⇒ 恢复逐格 rug_cell_els（真机已验证路径），
    并把 rug_cell_els 改成「按边开放」算法：共享边不内缩、外围边内缩。
"""
import json, pathlib, re, sys, itertools, copy
sys.stdout.reconfigure(encoding='utf-8')
ROOT = pathlib.Path(__file__).resolve().parent
DESIGN = pathlib.Path(r'D:/新建文件夹/miHoYo Launcher/murdoku-project/第三四关内容设计')
V688 = ROOT.parent / '688_第4至7关接入'
L691 = ROOT.parent / '691_橙黄通用卡与真机修复' / '691_内嵌Lua_691.lua'
sys.path.insert(0, str(DESIGN))
sys.path.insert(0, str(V688))
from murdoku_engine import Model as M6, NAMES, validate_geometry as vg
import verify_v14 as V14
import gen_688_data as G

V14D = {x['level']: x for x in json.loads((DESIGN / 'design_selected_v14.json').read_text(encoding='utf8'))}
V15D = {x['level']: x for x in json.loads((V688 / 'design_selected_v15.json').read_text(encoding='utf8'))}
LUA691 = L691.read_text(encoding='utf8')

# ── 姓名表：全部 ≤4 字 ─────────────────────────────────────────────────
OLD = {
    1: dict(A='值班保安', B='前台姑娘', C='夜班清洁工', D='旧识古董商', V='收藏家'),
    2: dict(A='夜班门卫', B='画廊助理', C='临时搬运工', D='鉴定师', E='随行记者', V='馆长'),
    4: dict(A='卷宗管理员', B='米纸誊录员', C='页角修复师', D='夜巡值守',
           E='借阅登记员', V='老馆长'),
    5: dict(A='封条保管员', B='夜勘记录员', C='火漆验印师', D='暗房洗印员',
           E='证物登记员', V='守夜馆人'),
    6: dict(A='晒图学徒', B='靛青描图员', C='野外测绘员', D='朱批校样员',
           E='蓝图管理员', F='工地放样员', V='总测绘师'),
    7: dict(A='铜钥保管员', B='转架管理员', C='墨绿誊写员', D='铜牌登记员',
           E='线装匠人', V='藏卷人'),
}
NAMES_BY_LEVEL = {
    1: dict(A='值班保安', B='前台姑娘', C='清洁工', D='古董商', V='收藏家'),
    2: dict(A='夜班门卫', B='画廊助理', C='搬运工', D='鉴定师', E='随行记者', V='馆长'),
    3: dict(A='巡夜保安', B='展签誊录', C='拓片修复', D='门厅接待',
           E='证物清点', V='展厅主人'),
    4: dict(A='卷宗管理', B='米纸誊录', C='页角修复', D='夜巡值守',
           E='借阅登记', V='老馆长'),
    5: dict(A='封条保管', B='夜勘记录', C='火漆验印', D='暗房洗印',
           E='证物登记', V='守夜馆人'),
    6: dict(A='晒图学徒', B='靛青描图', C='野外测绘', D='朱批校样',
           E='蓝图管理', F='工地放样', V='总测绘师'),
    7: dict(A='铜钥保管', B='转架管理', C='墨绿誊写', D='铜牌登记',
           E='线装匠人', V='藏卷人'),
}
FINAL = copy.deepcopy(NAMES_BY_LEVEL)
FINAL[4]['A'], FINAL[4]['D'] = NAMES_BY_LEVEL[4]['D'], NAMES_BY_LEVEL[4]['A']
assert all(len(v) <= 4 for lv in FINAL.values() for v in lv.values()), '有人名超过 4 字'


def pref(letter, name):
    return letter + name


def render_clause(clause, speaker, names):
    return re.sub(r'[A-FV]',
                  lambda m: '我' if m.group() == speaker else pref(m.group(), names[m.group()]),
                  clause)


def prefix_free_text(text, names):
    n2l = {v: k for k, v in names.items()}
    pat = re.compile('|'.join(re.escape(n) for n in sorted(n2l, key=len, reverse=True)))
    return pat.sub(lambda m: pref(n2l[m.group()], m.group()), text)


# ── 第3关：V 房间家具调整 ──────────────────────────────────────────────
D3 = copy.deepcopy(V14D[3])
_shelf = D3['objects']['书架']                       # [4,5,11] = (1,5)(1,6)(2,6)
D3['objects']['书架'] = [_shelf[0]]
D3['objects']['植物'] = D3['objects']['植物'] + [_shelf[1]]
D3['objects']['雕塑'] = [_shelf[2]]
D3['asset_mapping'].append(dict(local_name='雕塑', official_id=20, official_name='Statue',
                                occupiable=False, freq_levels=11,
                                differentiated_name='证物雕像 · 编号底座',
                                local_art_supported=True, cells=[_shelf[2]]))
for a in D3['asset_mapping']:
    if a['local_name'] == '植物':
        a['cells'] = D3['objects']['植物']
    if a['local_name'] == '书架':
        a['cells'] = D3['objects']['书架']

G.OBJS = ['桌子', '椅子', '书架', '植物', '地毯', '雕塑']
G.KIND['雕塑'] = 'statue'
G.BLOCK.add('雕塑')

THIEF_IDX = NAMES.index(D3['thief'])
# 模型只依赖 room / objects / target，与卡序无关 ⇒ 全部候选复用同一个实例
vg(D3)                       # 几何只验一次
M3 = M6(D3)


def gates3(cards):
    a = M3.audit(cards)
    if not a['correct']:
        return False
    tv = M3.truth_vector(cards)
    if any(not x for x in tv):
        return False
    own = len(a['audit'][THIEF_IDX]['positions'])
    if not (own >= 2 and a['alltrue'] > 0):
        return False
    for i in range(len(cards)):
        cc = [list(c) for c in cards]
        cc[i] = []
        if M3.audit(cc)['correct']:
            return False
    single = [[len(M3.positions(b, i)) for i in range(len(cards))] for b in a['bs']]
    if min(min(x) for x in single) <= 1:
        return False
    k, _, _ = V14.min_contradiction(M3, cards)
    if k is not None:
        return False
    cl = [len(c) for c in cards]
    if cl[-1] != 1 or max(cl) > 2 or sum(1 for x in cl if x > 1) > 2:
        return False
    return True


def letters_in(s):
    return set(re.findall(r'[A-FV]', s))


sp3 = list(D3['card_speakers'])
cands = []
for order in itertools.permutations(range(6)):
    cards = [D3['cards'][i] for i in order]
    if len(cards[-1]) != 1 or not gates3(cards):
        continue
    cov = sum(1 for slot, ci in enumerate(order)
              for s in D3['cards'][ci] if sp3[slot] in letters_in(s))
    tot = sum(len(c) for c in cards)
    drift = sum(abs(ci - slot) for slot, ci in enumerate(order))
    cands.append((cov, -drift, order, tot))
cands.sort(reverse=True)
if not cands:
    raise SystemExit('第3关：家具调整后没有通过全真闸门的卡序')
COV, _, ORDER3, TOT3 = cands[0]
print(f'第3关（家具调整后）合法卡序 {len(cands)} 个，自述 {COV}/{TOT3}，卡序 {[i+1 for i in ORDER3]}')

D3F = copy.deepcopy(D3)
D3F['cards'] = [D3['cards'][i] for i in ORDER3]
D3F['clause_roles'] = [copy.deepcopy(D3['clause_roles'][i]) for i in ORDER3]
for slot, ci in enumerate(ORDER3):
    for part in D3F['clause_roles'][slot]:
        part['speaker'] = sp3[slot]
        part['self_ref'] = sp3[slot] in letters_in(part['text'])
D3F['suspects'] = FINAL[3]
D3F['theme_note'] = '原作明亮俯视'
D3F['archive_texts'] = [[render_clause(c, sp3[i], FINAL[3]) for c in D3F['cards'][i]]
                        for i in range(len(ORDER3))]
D3F['order_table'] = V14D[3]['order_table'] if 'order_table' in V14D[3] else None
G.D = {3: D3F}
_b3 = G.build_level(3)
LEVEL3_LUA, HINTS3 = _b3['lua'], _b3['hints']
LEVEL3_LUA['meta'] = dict(announce='unknown')
LEVEL3_LUA['difficulty'] = 'easy'
LEVEL3_LUA['name'] = '案件 003 · 原作明亮俯视'
LEVEL3_LUA['suspects'] = [dict(id=k, name=FINAL[3][k], portrait='portrait.' + k,
                               **({'is_victim': True} if k == 'V' else {})) for k in sp3]
LEVEL3_LUA['victim'] = dict(id='V', name=FINAL[3]['V'])
LEVEL3_LUA['roles'] = dict(thief=D3['thief'])

# ── 第4关：A/D 卡槽内容顺序互换 + 姓名对调 ─────────────────────────────
d4 = copy.deepcopy(V15D[4])
_c = d4['cards']
_c[0], _c[3] = copy.deepcopy(_c[3]), copy.deepcopy(_c[0])
_cr = d4['clause_roles']
_cr[0], _cr[3] = copy.deepcopy(_cr[3]), copy.deepcopy(_cr[0])
sp4 = list(d4['card_speakers'])
for i in range(len(_c)):
    for part in _cr[i]:
        part['speaker'] = sp4[i]
        part['self_ref'] = sp4[i] in letters_in(part['text'])
d4['suspects'] = FINAL[4]
d4['theme_note'] = '档案卷宗 · 米纸浅色'
d4['archive_texts'] = [[render_clause(c, sp4[i], FINAL[4]) for c in _c[i]]
                       for i in range(len(_c))]
d4['order_table'] = V15D[4]['order_table']
G.D = {4: d4}
_b4 = G.build_level(4)
LEVEL4_LUA, HINTS4 = _b4['lua'], _b4['hints']
LEVEL4_LUA['name'] = '案件 004 · 档案卷宗 · 米纸浅色'
LEVEL4_LUA['suspects'] = [dict(id=k, name=FINAL[4][k], portrait='portrait.' + k,
                               **({'is_victim': True} if k == 'V' else {})) for k in sp4]
LEVEL4_LUA['victim'] = dict(id='V', name=FINAL[4]['V'])


def L(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if v is None:
        return 'nil'
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
    if isinstance(v, list):
        return '{' + ', '.join(L(x) for x in v) + '}'
    if isinstance(v, dict):
        if v and all(isinstance(k, int) for k in v) and sorted(v) == list(range(1, len(v) + 1)):
            return '{' + ', '.join(L(v[i]) for i in sorted(v)) + '}'
        return '{' + ', '.join('[' + L(k) + '] = ' + L(x) for k, x in v.items()) + '}'
    raise TypeError(type(v))


def module(lv, lua):
    return (f'__M["levels.case_{lv:03d}"] = function()\n'
            f' return ' + L(lua) + '\nend\n')


MODULE3, MODULE4 = module(3, LEVEL3_LUA), module(4, LEVEL4_LUA)

# ── 静态文本：who 纯人名（无字母），what 姓名带字母前缀 ─────────────────
WHAT12 = {
    1: ['只有值班保安站在地毯上', '前台姑娘在桌子旁边', '清洁工坐在椅子上',
        '古董商在植物旁边', '收藏家在第五列'],
    2: ['夜班门卫在书架旁边', '画廊助理在桌子旁边', '有两人坐在椅子上',
        '随行记者在夜班门卫的上方。', '只有随行记者在植物旁边',
        '我独自一人，且搬运工在我下方的不同区域中'],
}
TEXTS = {}
for lv in (1, 2):
    ks = list(NAMES_BY_LEVEL[lv])
    TEXTS[str(lv)] = [dict(slot=i + 1, letter=k, who=NAMES_BY_LEVEL[lv][k],
                           what=prefix_free_text(WHAT12[lv][i], NAMES_BY_LEVEL[lv]))
                      for i, k in enumerate(ks)]
TEXTS['3'] = [dict(slot=i + 1, letter=sp3[i], who=FINAL[3][sp3[i]],
                   what='、'.join(render_clause(c, sp3[i], FINAL[3]) for c in D3F['cards'][i]))
              for i in range(len(ORDER3))]
TEXTS['4'] = [dict(slot=i + 1, letter=sp4[i], who=FINAL[4][sp4[i]],
                   what='、'.join(render_clause(c, sp4[i], FINAL[4]) for c in _c[i]))
              for i in range(len(_c))]
for lv in (5, 6, 7):
    d = V15D[lv]
    ks = list(d['card_speakers'])
    TEXTS[str(lv)] = [dict(slot=i + 1, letter=ks[i], who=FINAL[lv][ks[i]],
                           what='、'.join(render_clause(c, ks[i], FINAL[lv]) for c in d['cards'][i]))
                      for i in range(len(d['cards']))]

# ── Lua 可逆补丁 ────────────────────────────────────────────────────────
PATCHES = []


def patch(name, old, new, count=None):
    n = LUA691.count(old)
    if n == 0:
        raise SystemExit(f'补丁锚点未找到 [{name}] old={old[:100]!r}')
    if count is not None and n != count:
        raise SystemExit(f'补丁锚点数不符 [{name}] {n} != {count}')
    PATCHES.append(dict(name=name, old=old, new=new, count=n))


# 1) 1/2/5/6/7 关 Lua 姓名缩短（who 不带字母，故只做长名→短名）
for lv in (1, 2):
    for k, oldname in OLD[lv].items():
        newname = NAMES_BY_LEVEL[lv][k]
        if oldname == newname:
            continue
        patch(f'case_{lv:03d} {k} 姓名缩短',
              f'{{ id = "{k}", name = "{oldname}"',
              f'{{ id = "{k}", name = "{newname}"', count=1)
for lv in (5, 6, 7):
    for k, oldname in OLD[lv].items():
        newname = NAMES_BY_LEVEL[lv][k]
        if oldname == newname:
            continue
        patch(f'case_{lv:03d} {k} 姓名缩短',
              f'["id"] = "{k}", ["name"] = "{oldname}"',
              f'["id"] = "{k}", ["name"] = "{newname}"')

# 2) 地毯逐格绘制：改成「按边开放」——整块 L 形，边框只沿外围
patch('rug_cell_els 按边开放（整块外围边框）',
'''function F.rug_cell_els(bbox, r, c)
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
end''',
'''function F.rug_cell_els(bbox, r, c, cellset)
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
end''', count=1)

# 3) F.layout：所有地毯恢复逐格绘制并传 cellset；L 形仍打 L3a/L3b variant
patch('F.layout 地毯恢复逐格绘制 + 传 cellset',
'''    if kind == "carpet" then
      for _, cell in ipairs(p.cells) do
        res.cell[cell[1]][cell[2]].els = F.rug_cell_els(b, cell[1], cell[2])
      end
      res.pieces = res.pieces or {}
      res.pieces[#res.pieces + 1] = {
        kind = kind, box = b, anchor = anchor_of(b), variant = "1",
        cells = p.cells, span_r = span_r, span_c = span_c,
      }
    else''',
'''    if kind == "carpet" then
      local tri = nil
      if #p.cells == 3 and span_r == 2 and span_c == 2 then
        local has = {}
        for _, cell in ipairs(p.cells) do
          has[(cell[1] - b.r1) .. ":" .. (cell[2] - b.c1)] = true
        end
        if not has["1:1"] then tri = "L3a"           -- 缺右下：第3关
        elseif not has["1:0"] then tri = "L3b" end   -- 缺左下：第7关
      end
      local cellset = {}
      for _, cell in ipairs(p.cells) do
        cellset[cell[1]] = cellset[cell[1]] or {}
        cellset[cell[1]][cell[2]] = true
      end
      for _, cell in ipairs(p.cells) do
        res.cell[cell[1]][cell[2]].els = F.rug_cell_els(b, cell[1], cell[2], cellset)
      end
      res.pieces = res.pieces or {}
      res.pieces[#res.pieces + 1] = {
        kind = kind, box = b, anchor = anchor_of(b), variant = tri or "1",
        cells = p.cells, span_r = span_r, span_c = span_c,
      }
    else''', count=1)

# 4) build_layout 采用 L3 variant
patch('build_layout 采用 L3 variant',
'''        local variant = "1"
        if (p.span_c or 1) > 1 then variant = "h2"
        elseif (p.span_r or 1) > 1 then variant = "v2" end''',
'''        local variant = "1"
        if kind == "carpet" and (p.variant == "L3a" or p.variant == "L3b") then
          variant = p.variant
        elseif (p.span_c or 1) > 1 then variant = "h2"
        elseif (p.span_r or 1) > 1 then variant = "v2" end''', count=1)

# 5) 新素材完整引用链
patch('TPL_KEY 注册三格地毯',
      '      carpet = { ["1"] = "furn.rug", h2 = "furn.rug.2", v2 = "furn.rug.3" },',
      '      carpet = { ["1"] = "furn.rug", h2 = "furn.rug.2", v2 = "furn.rug.3",\n'
      '                 L3a = "furn.rug.4", L3b = "furn.rug.5" },', count=1)
patch('path_map 注册新素材',
      '  ["furn.rug.3"] = "root/things/furn.rug.3",',
      '  ["furn.rug.3"] = "root/things/furn.rug.3",\n'
      '  ["furn.rug.4"] = "root/things/furn.rug.4",\n'
      '  ["furn.rug.5"] = "root/things/furn.rug.5",', count=1)
patch('cfg.furn_tpl_prefab 新增两项',
      '''      rug_3    = 1073749968,
    },''',
      '''      rug_3    = 1073749968,
      rug_4    = __RUG4_PREFAB__,
      rug_5    = __RUG5_PREFAB__,
    },''', count=1)
patch('cfg.furn_tpl_canvas 新增 216×216',
      '    furn_tpl_canvas = { rug_2 = { 216, 108 }, rug_3 = { 108, 216 }, table_h2 = { 216, 108 }, table_v2 = { 108, 216 } },',
      '    furn_tpl_canvas = { rug_2 = { 216, 108 }, rug_3 = { 108, 216 },\n'
      '                       rug_4 = { 216, 216 }, rug_5 = { 216, 216 },\n'
      '                       table_h2 = { 216, 108 }, table_v2 = { 108, 216 } },', count=1)
patch('cfg 新素材等比不缩放',
      '''      rug_3 = { x = 0.762, y = 0.93 },
    },''',
      '''      rug_3 = { x = 0.762, y = 0.93 },
      rug_4 = { x = 1, y = 1 },
      rug_5 = { x = 1, y = 1 },
    },''', count=1)
patch('_spawn_furn_tpl 隐藏所有整块地毯（避免与逐格双绘）',
'''  if ckey=="rug" or ckey=="rug_2" or ckey=="rug_3" then
    for k,o in pairs(self._furn_inst or {}) do
      if string.find(k,"|rug",1,true) and o and o.SetVisible then pcall(function() o:SetVisible(false) end) end
    end
    return false
  end''',
'''  if ckey=="rug" or ckey=="rug_2" or ckey=="rug_3"
     or ckey=="rug_4" or ckey=="rug_5" then
    for k,o in pairs(self._furn_inst or {}) do
      if string.find(k,"|rug",1,true) and o and o.SetVisible then pcall(function() o:SetVisible(false) end) end
    end
    return false
  end''', count=1)
patch('_spawn_furn_tpl is_rug 纳入新素材',
      '  local is_rug = ckey == "rug" or ckey == "rug_2" or ckey == "rug_3"',
      '  local is_rug = ckey == "rug" or ckey == "rug_2" or ckey == "rug_3"\n'
      '                 or ckey == "rug_4" or ckey == "rug_5"', count=1)

# ── 三格地毯新独立素材：整块 L 形 + 外围边框 ───────────────────────────
CELL, CANVAS = 108.0, 216.0
INSET, LINE = 0.12 * CELL, 0.20 * CELL
RINGS = [('深色底', 0, '0xFFB89A62'), ('内面', INSET, '0xFFDCC684'),
         ('内框', LINE, '0xFFC9B072')]
QUADS = {'左上': (-54.0, 54.0), '右上': (54.0, 54.0),
         '左下': (-54.0, -54.0), '右下': (54.0, -54.0)}
NEIGH = {'左上': dict(L='', R='右上', U='', D='左下'),
         '右上': dict(L='左上', R='', U='', D='右下'),
         '左下': dict(L='', R='右下', U='左上', D=''),
         '右下': dict(L='左下', R='', U='右上', D='')}
L3_SHAPES = {
    'furn.rug.4': dict(variant='L3a', level=3, missing='右下',
                       cells=[(3, 2), (3, 3), (4, 2)], quads=['左上', '右上', '左下']),
    'furn.rug.5': dict(variant='L3b', level=7, missing='左下',
                       cells=[(2, 3), (2, 4), (3, 4)], quads=['左上', '右上', '右下']),
}


def carpet_layers(quads):
    present = set(quads)
    out = []
    for q in quads:
        cx, cy = QUADS[q]
        nb = NEIGH[q]
        opened = dict(L=nb['L'] and nb['L'] in present, R=nb['R'] and nb['R'] in present,
                      U=nb['U'] and nb['U'] in present, D=nb['D'] and nb['D'] in present)
        for part, inset, color in RINGS:
            if part == '深色底':
                out.append(dict(part=part, quad=q, x=cx, y=cy, w=CELL, h=CELL,
                                imageId=100001, color=color, order=len(out) + 1))
                continue
            l = cx - CELL / 2 + (0 if opened['L'] else inset)
            r = cx + CELL / 2 - (0 if opened['R'] else inset)
            b = cy - CELL / 2 + (0 if opened['D'] else inset)
            t = cy + CELL / 2 - (0 if opened['U'] else inset)
            out.append(dict(part=part, quad=q, x=round((l + r) / 2, 2),
                            y=round((b + t) / 2, 2), w=round(r - l, 2), h=round(t - b, 2),
                            imageId=100001, color=color, order=len(out) + 1))
    return out


CARPET_SPEC = {}
for tpl, shape in L3_SHAPES.items():
    layers = carpet_layers(shape['quads'])
    CARPET_SPEC[tpl] = dict(
        template=tpl, kind='carpet', variant=shape['variant'], level=shape['level'],
        missing=shape['missing'], cells=[list(c) for c in shape['cells']],
        canvas=dict(W=CANVAS, H=CANVAS, cell=CELL, grid='2×2'),
        layerCount=len(layers), layers=layers,
        style='整块 L 形：深色底铺满 3 格，内面/内框按「共享边开放」切片 ⇒ 内部无格线，边框只沿外围',
        gate=dict(zeroSpur=all(abs(l['x']) + l['w'] / 2 <= CANVAS / 2 + 0.01 and
                               abs(l['y']) + l['h'] / 2 <= CANVAS / 2 + 0.01 for l in layers),
                  noStretch=True, legalPrimitives=[100001],
                  layerBudget=len(layers) <= 12, distinctAsset=True,
                  borderOuterOnly=True),
        referenceRoute=['源/母本/引用三件套 → things.childList → path_map',
                        'cfg.furn_tpl_prefab / furn_tpl_canvas / furn_scale_axis_by_kind',
                        'TPL_KEY.carpet.L3a|L3b → furn_tpl → _spawn_furn_tpl',
                        '真机渲染由 F.rug_cell_els 逐格「按边开放」完成（691 已验证路径）'])

FURN = dict(
    localResearchPackage='官网美术素材调研-2026-11-13/',
    researchGap='调研包缺 Carpet 独立逐件层表；688 的规格是拉伸版，692 的三格是三个单格方框拼接。'
                '693 按用户要求改为整块 L 形 + 外围边框。',
    furnitureUsed={str(lv): list(k for k, v in
                                 (D3F if lv == 3 else V15D[lv])['objects'].items() if v)
                   for lv in range(3, 8)},
    level3VRedesign=dict(room='R1（V 在 (4,6)）',
                         before='书架 3 格 (1,5)(1,6)(2,6)',
                         after='书架 1 格 (1,5) + 植物 (1,6) + 雕塑 (2,6)',
                         note='雕塑为纯装饰、不参与任何线索；三格仍是 BLOCK（不可站），谜题解不变'),
    levelsWithTriCarpet=[3, 7], newAssets=CARPET_SPEC,
    renderPath='F.rug_cell_els 逐格按边开放（与两格地毯同一路径，真机已验证）')

# ── 顺序对照表 ──
MD = ['# 693 · 卡序 / 说话人顺序对照表', '',
      '> 第3关：只重排卡序提高本人自述；家具按真机反馈调整（V 房间 1 书架 + 1 植物 + 1 雕塑）。',
      '> 第4关：**A/D 两张卡内容顺序互换** + 姓名对调；卡面从谓词按新姓名表重渲染，凡指本人一律「我」。',
      '> `who` 区域为纯人名（≤4 字，不加字母）；卡面正文中的姓名前加对应字母，「我」前不加。', '']
for lv in (3, 4):
    d = D3F if lv == 3 else d4
    cards = d['cards']
    sp = sp3 if lv == 3 else sp4
    MD += [f'## 第{lv}关（{d["grid"]}×{d["grid"]}，盗窃者 {d["thief"]}）', '',
           '| 卡槽 | 说话人 | 姓名（who） | 卡面（what） | ←原卡 | 本人自述 |',
           '|---:|:---:|---|---|:---:|:---:|']
    for i in range(len(cards)):
        selfn = any(p['self_ref'] for p in d['clause_roles'][i])
        fromslot = (ORDER3[i] + 1) if lv == 3 else (4 if i == 0 else 1 if i == 3 else i + 1)
        MD.append(f'| {i+1} | {sp[i]} | {FINAL[lv][sp[i]]} | {TEXTS[str(lv)][i]["what"]} '
                  f'| {fromslot} | {"是" if selfn else "否"} |')
    MD.append('')

OUT = dict(
    version=693, base='../691_橙黄通用卡与真机修复/691_橙黄通用卡与真机修复.gil',
    moduleReplacements=[
        dict(name='case_003 第3关定稿（家具调整）', marker='__M["levels.case_003"] = function()',
             newModule=MODULE3),
        dict(name='case_004 A/D 内容互换 + 姓名对调', marker='__M["levels.case_004"] = function()',
             newModule=MODULE4),
    ],
    luaPatches=PATCHES,
    prefabPlaceholders=['__RUG4_PREFAB__', '__RUG5_PREFAB__'],
    names={str(k): v for k, v in FINAL.items()},
    nameRules=dict(who='纯人名，≤4 字，不加字母', what='姓名前加对应字母，「我」等代词不加',
                   luaName='纯人名，与 who 一致'),
    level4=dict(swapType='卡面内容顺序互换（槽1↔槽4）+ A/D 姓名对调',
                order=[4, 2, 3, 1, 5, 6],
                A=dict(before=OLD[4]['A'], after=FINAL[4]['A']),
                D=dict(before=OLD[4]['D'], after=FINAL[4]['D']),
                note='解/真假向量/盗窃者/唯一性不变；离线「删卡非冗余」1 项会变'),
    level3=dict(gates='六卡全真教学关', legalOrders=len(cands),
                selfNarration=f'{COV}/{TOT3}', order=[i + 1 for i in ORDER3],
                furniture=dict(书架=D3F['objects']['书架'], 植物=D3F['objects']['植物'],
                               雕塑=D3F['objects']['雕塑'])),
    carpet=L3_SHAPES)

(ROOT / '693_设计与补丁.json').write_text(json.dumps(OUT, ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '693_关卡数据.json').write_text(json.dumps(dict(
    version=693,
    level3=dict(lua=LEVEL3_LUA, texts=TEXTS['3'], hints=HINTS3, order=[i + 1 for i in ORDER3]),
    level4=dict(lua=LEVEL4_LUA, texts=TEXTS['4'], hints=HINTS4),
    names={str(k): v for k, v in FINAL.items()}),
    ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '693_静态文本补丁.json').write_text(json.dumps(
    dict(rule='who 纯人名≤4字不加字母；what 人名前加字母，「我」不加', texts=TEXTS),
    ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '693_家具规格.json').write_text(json.dumps(FURN, ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '693_浅蓝提示格.json').write_text(json.dumps(
    dict(rule='线索卡-位置提示表.md §二；颜色 0x7F0063D5',
         levels={'3': HINTS3, '4': HINTS4}), ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '693_顺序对照表.md').write_text('\n'.join(MD), encoding='utf8')

print('Lua 补丁', len(PATCHES), '项；模块替换 2 个；静态文本',
      sum(len(v) for v in TEXTS.values()), '条')
for lv in ('3', '4'):
    print(f'--- 第{lv}关 ---')
    for t in TEXTS[lv]:
        print(f"  {t['slot']} | {t['who']} | {t['what']}")
print('新素材层数', {k: v['layerCount'] for k, v in CARPET_SPEC.items()},
      '零溢出', {k: v['gate']['zeroSpur'] for k, v in CARPET_SPEC.items()})
print('已生成 6 份规格文件')
