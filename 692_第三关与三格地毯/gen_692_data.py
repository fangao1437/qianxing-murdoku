"""692 · 基于 691 写入第3关 + 全关字母前缀 + 第4关 A/D 姓名对调 + 三格地毯新素材

口径（用户 2026-11-15 确认）：
  · 第3关按 v14 设计图整体写入（六卡全真教学关，按 34 关全真闸门复验）；
    像 1/2 关一样起中文名；卡序只重排以最大化本人自述，谓词/几何/答案零改动。
  · 第4关 A/D **姓名对调**（不是卡序对调）：姓名标签互换，卡面从谓词按新姓名表
    重新渲染，凡指说话人本人一律写「我」；谓词、卡序、答案、真假向量零改动。
  · 所有关卡的「人名前加对应字母」，只加字母、不加任何分隔符；「我」等代词前不加。
    作用于 who 静态文本、Lua suspects.name / victim.name、what 卡面里出现的姓名。
  · 三格 L 形地毯**单独新建素材**（2×2 画布、3 个独立格位、不拉伸），
    完全按现有家具素材引用路线：源/母本/引用三件套 + childList + path_map +
    cfg.furn_tpl_prefab/canvas/axis + TPL_KEY + F.layout variant + _spawn_furn_tpl。

产出（全部离线，不碰 .gil）：
  692_设计与补丁.json    Lua 可逆补丁 + 模块替换 + 静态文本 + 地毯模板规格
  692_关卡数据.json      第3关完整 Lua table + 全关姓名表
  692_静态文本补丁.json  who/what/letter 逐条
  692_家具规格.json      三格地毯新素材规格 + 本地调研包映射
  692_浅蓝提示格.json    第3关逐卡提示格
  692_顺序对照表.md      第3关 + 第4关（对调后）供用户「只验证顺序」
"""
import json, pathlib, re, sys, itertools, copy
sys.stdout.reconfigure(encoding='utf-8')
ROOT = pathlib.Path(__file__).resolve().parent
DESIGN = pathlib.Path(r'D:/新建文件夹/miHoYo Launcher/murdoku-project/第三四关内容设计')
V688 = ROOT.parent / '688_第4至7关接入'
L691 = ROOT.parent / '691_橙黄通用卡与真机修复' / '691_内嵌Lua_691.lua'
sys.path.insert(0, str(DESIGN))
sys.path.insert(0, str(V688))
from murdoku_engine import Model as M6, NAMES
import verify_v14 as V14
import gen_688_data as G

V14D = {x['level']: x for x in json.loads((DESIGN / 'design_selected_v14.json').read_text(encoding='utf8'))}
V15D = {x['level']: x for x in json.loads((V688 / 'design_selected_v15.json').read_text(encoding='utf8'))}
LUA691 = L691.read_text(encoding='utf8')

# ── 姓名表（1/2 关沿用 691 存档既有中文名；3 关新命名；4~7 关沿用 688） ──
NAMES_BY_LEVEL = {
    1: dict(A='值班保安', B='前台姑娘', C='夜班清洁工', D='旧识古董商', V='收藏家'),
    2: dict(A='夜班门卫', B='画廊助理', C='临时搬运工', D='鉴定师', E='随行记者', V='馆长'),
    3: dict(A='巡夜保安', B='展签誊录员', C='拓片修复师', D='门厅接待员',
           E='证物清点员', V='展厅主人'),
    4: dict(A='卷宗管理员', B='米纸誊录员', C='页角修复师', D='夜巡值守',
           E='借阅登记员', V='老馆长'),
    5: dict(A='封条保管员', B='夜勘记录员', C='火漆验印师', D='暗房洗印员',
           E='证物登记员', V='守夜馆人'),
    6: dict(A='晒图学徒', B='靛青描图员', C='野外测绘员', D='朱批校样员',
           E='蓝图管理员', F='工地放样员', V='总测绘师'),
    7: dict(A='铜钥保管员', B='转架管理员', C='墨绿誊写员', D='铜牌登记员',
           E='线装匠人', V='藏卷人'),
}
# 第4关 A/D 姓名对调（用户确认），仅标签层，谜题零改动
FINAL = copy.deepcopy(NAMES_BY_LEVEL)
FINAL[4]['A'], FINAL[4]['D'] = NAMES_BY_LEVEL[4]['D'], NAMES_BY_LEVEL[4]['A']


def pref(letter, name):
    """人名前只加字母，不加任何分隔符。"""
    return letter + name


def render_clause(clause, speaker, names):
    """谓词 → 卡面：字母换成「我」(说话人本人) 或「字母+姓名」(他人)。"""
    return re.sub(r'[A-FV]',
                  lambda m: '我' if m.group() == speaker else pref(m.group(), names[m.group()]),
                  clause)


def prefix_free_text(text, names):
    """1/2 关自由文本：出现的中文姓名前加对应字母；「我」等代词不加。"""
    n2l = {v: k for k, v in names.items()}
    pat = re.compile('|'.join(re.escape(n) for n in sorted(n2l, key=len, reverse=True)))
    return pat.sub(lambda m: pref(n2l[m.group()], m.group()), text)


# ── 第3关：全真闸门复验 + 卡序枚举 ─────────────────────────────────────
D3 = V14D[3]
M3 = M6(D3)
THIEF_IDX = NAMES.index(D3['thief'])


def gates3(cards):
    """34 关定稿第3关（六卡全真教学关）全闸门。"""
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
    if k is not None:                       # 全真关不应有矛盾子集
        return False
    cl = [len(c) for c in cards]
    if cl[-1] != 1 or max(cl) > 2 or sum(1 for x in cl if x > 1) > 2:
        return False
    return True


def letters_in(s):
    return set(re.findall(r'[A-FV]', s))


def best_order3():
    sp = list(D3['card_speakers'])
    cand = []
    for order in itertools.permutations(range(len(D3['cards']))):
        cards = [D3['cards'][i] for i in order]
        if len(cards[-1]) != 1:
            continue
        if not gates3(cards):
            continue
        cov = sum(1 for slot, ci in enumerate(order)
                  for s in D3['cards'][ci] if sp[slot] in letters_in(s))
        tot = sum(len(c) for c in cards)
        drift = sum(abs(ci - slot) for slot, ci in enumerate(order))
        cand.append((cov, -drift, order, tot))
    cand.sort(reverse=True)
    return cand


CANDS = best_order3()
if not CANDS:
    raise SystemExit('第3关：没有通过全部全真闸门的卡序')
COV, _, ORDER3, TOT3 = CANDS[0]
BASELINE3 = sum(1 for cr in D3['clause_roles'] for p in cr if p.get('self_ref'))
print(f'第3关 全真闸门合法卡序 {len(CANDS)} 个，选自述 {COV}/{TOT3}（v14 {BASELINE3}/{TOT3}），'
      f'卡序 {[i+1 for i in ORDER3]}')

# 第3关定稿（谓词/几何/答案与 v14 逐字段相同，只重排卡序）
D3F = copy.deepcopy(D3)
D3F['cards'] = [D3['cards'][i] for i in ORDER3]
D3F['clause_roles'] = [copy.deepcopy(D3['clause_roles'][i]) for i in ORDER3]
sp3 = list(D3['card_speakers'])
for slot, ci in enumerate(ORDER3):
    for part in D3F['clause_roles'][slot]:
        part['speaker'] = sp3[slot]
        part['self_ref'] = sp3[slot] in letters_in(part['text'])
D3F['names'] = FINAL[3]
D3F['suspects'] = FINAL[3]                    # 供 688 build_level 取姓名
D3F['theme_note'] = '原作明亮俯视'
D3F['archive_texts'] = [[render_clause(c, sp3[i], FINAL[3]) for c in D3F['cards'][i]]
                        for i in range(len(ORDER3))]
D3F['order_table'] = [dict(slot=i + 1, speaker=sp3[i], name=FINAL[3][sp3[i]],
                           from_slot=ORDER3[i] + 1,
                           predicate=D3F['cards'][i],
                           self_narrated=any(p['self_ref'] for p in D3F['clause_roles'][i]))
                      for i in range(len(ORDER3))]

# ── 第3关 Lua table（复用 688 的几何/提示/序列化，全真关无 false_clue） ──
G.D = {3: D3F}
LEVEL3_LUA = G.build_level(3)['lua']
# 全真教学关：不预告假卡（false_clue = nil），victim / 姓名 / 难度按定稿
LEVEL3_LUA['meta'] = dict(announce='unknown')
LEVEL3_LUA['difficulty'] = 'easy'
LEVEL3_LUA['name'] = '案件 003 · 原作明亮俯视'
LEVEL3_LUA['suspects'] = [dict(id=k, name=pref(k, FINAL[3][k]), portrait='portrait.' + k,
                               **({'is_victim': True} if k == 'V' else {}))
                          for k in sp3]
LEVEL3_LUA['victim'] = dict(id='V', name=pref('V', FINAL[3]['V']))
LEVEL3_LUA['roles'] = dict(thief=D3['thief'])
# hint_preview 由 build_level 按重排后的谓词生成（G.build_level 用 D3F.cards）
LEVEL3_DATA = dict(level=3, lua=LEVEL3_LUA,
                   texts=[dict(slot=i + 1, letter=sp3[i], who=pref(sp3[i], FINAL[3][sp3[i]]),
                               what='、'.join(render_clause(c, sp3[i], FINAL[3])
                                             for c in D3F['cards'][i]))
                          for i in range(len(ORDER3))],
                   hints=G.build_level(3)['hints'],
                   order_table=D3F['order_table'])


def L(v):
    """Lua 值序列化（与 688 同款，仅 [--key--] / 数字 / 字符串 / 布尔 / 数组）。"""
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


MODULE3 = ('__M["levels.case_003"] = function()\n'
           ' return ' + L(LEVEL3_LUA) + '\n'
           'end\n')

# ── 静态文本：全 7 关 ───────────────────────────────────────────────────
# 从 691 存档读取的 1/2 关既有卡面（who 用 Lua 姓名表，what 用自由文本）
WHAT12 = {
    1: ['只有值班保安站在地毯上', '前台姑娘在桌子旁边', '夜班清洁工坐在椅子上',
        '旧识古董商在植物旁边', '收藏家在第五列'],
    2: ['夜班门卫在书架旁边', '画廊助理在桌子旁边', '有两人坐在椅子上',
        '随行记者在夜班门卫的上方。', '只有随行记者在植物旁边',
        '我独自一人，且临时搬运工在我下方的不同区域中'],
}
TEXTS = {'3': LEVEL3_DATA['texts']}
for lv in (1, 2):
    ks = list(NAMES_BY_LEVEL[lv])
    TEXTS[str(lv)] = [dict(slot=i + 1, letter=k, who=pref(k, NAMES_BY_LEVEL[lv][k]),
                           what=prefix_free_text(WHAT12[lv][i], NAMES_BY_LEVEL[lv]))
                      for i, k in enumerate(ks)]
for lv in (4, 5, 6, 7):
    d = V15D[lv]
    ks = list(d['card_speakers'])
    TEXTS[str(lv)] = [dict(slot=i + 1, letter=ks[i],
                           who=pref(ks[i], FINAL[lv][ks[i]]),
                           what='、'.join(render_clause(c, ks[i], FINAL[lv])
                                         for c in d['cards'][i]))
                      for i in range(len(d['cards']))]

# ── Lua 可逆补丁 ────────────────────────────────────────────────────────
PATCHES = []


def patch(name, old, new, count=1):
    n = LUA691.count(old)
    if n != count:
        raise SystemExit(f'补丁锚点数不符 [{name}] 期望 {count} 实得 {n}\nold={old[:120]!r}')
    PATCHES.append(dict(name=name, old=old, new=new, count=count))


# 1) 1/2 关（多行格式）suspects 姓名加字母；V 的锚点在 suspects 与 victim 各出现一次，
#    一次 split/join 同时覆盖两处，无需单独 victim 补丁。
for lv in (1, 2):
    for k, name in NAMES_BY_LEVEL[lv].items():
        old = f'{{ id = "{k}", name = "{name}"'
        patch(f'case_{lv:03d} {k} 姓名前缀', old,
              f'{{ id = "{k}", name = "{pref(k, name)}"', count=LUA691.count(old))

# 2) 4~7 关（压缩格式）suspects 姓名加字母；第4关 A/D 姓名对调。V 同上覆盖 victim。
for lv in (4, 5, 6, 7):
    for k, oldname in NAMES_BY_LEVEL[lv].items():
        newname = FINAL[lv][k]
        old = f'["id"] = "{k}", ["name"] = "{oldname}"'
        new = f'["id"] = "{k}", ["name"] = "{pref(k, newname)}"'
        patch(f'case_{lv:03d} {k} 姓名前缀/对调', old, new, count=LUA691.count(old))

# 3) 三格地毯：F.layout 识别 L 形三连，走专用模板且不再逐格双绘
patch('F.layout 三格 L 地毯 variant',
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
      if tri == nil then
        for _, cell in ipairs(p.cells) do
          res.cell[cell[1]][cell[2]].els = F.rug_cell_els(b, cell[1], cell[2])
        end
      end
      res.pieces = res.pieces or {}
      res.pieces[#res.pieces + 1] = {
        kind = kind, box = b, anchor = anchor_of(b), variant = tri or "1",
        cells = p.cells, span_r = span_r, span_c = span_c,
      }
    else''')

# 4) build_layout：carpet 优先采用 F.layout 给出的 L 形 variant
patch('build_layout 采用 L3 variant',
      '''        local variant = "1"
        if (p.span_c or 1) > 1 then variant = "h2"
        elseif (p.span_r or 1) > 1 then variant = "v2" end''',
      '''        local variant = "1"
        if kind == "carpet" and (p.variant == "L3a" or p.variant == "L3b") then
          variant = p.variant
        elseif (p.span_c or 1) > 1 then variant = "h2"
        elseif (p.span_r or 1) > 1 then variant = "v2" end''')

# 5) TPL_KEY 注册两个新模板
patch('TPL_KEY 注册三格地毯',
      '      carpet = { ["1"] = "furn.rug", h2 = "furn.rug.2", v2 = "furn.rug.3" },',
      '      carpet = { ["1"] = "furn.rug", h2 = "furn.rug.2", v2 = "furn.rug.3",\n'
      '                 L3a = "furn.rug.4", L3b = "furn.rug.5" },')

# 6) path_map 注册（与现有家具同一查找链）
patch('path_map 注册新素材',
      '  ["furn.rug.3"] = "root/things/furn.rug.3",',
      '  ["furn.rug.3"] = "root/things/furn.rug.3",\n'
      '  ["furn.rug.4"] = "root/things/furn.rug.4",\n'
      '  ["furn.rug.5"] = "root/things/furn.rug.5",')

# 7) cfg：prefab 兜底 / canvas 216×216 / 等比不缩放
patch('cfg.furn_tpl_prefab 新增两项',
      '''      rug_3    = 1073749968,
    },''',
      '''      rug_3    = 1073749968,
      rug_4    = __RUG4_PREFAB__,
      rug_5    = __RUG5_PREFAB__,
    },''')
patch('cfg.furn_tpl_canvas 新增 216×216',
      '    furn_tpl_canvas = { rug_2 = { 216, 108 }, rug_3 = { 108, 216 }, table_h2 = { 216, 108 }, table_v2 = { 108, 216 } },',
      '    furn_tpl_canvas = { rug_2 = { 216, 108 }, rug_3 = { 108, 216 },\n'
      '                       rug_4 = { 216, 216 }, rug_5 = { 216, 216 },\n'
      '                       table_h2 = { 216, 108 }, table_v2 = { 108, 216 } },')
patch('cfg 新素材等比不缩放',
      '''      rug_3 = { x = 0.762, y = 0.93 },
    },''',
      '''      rug_3 = { x = 0.762, y = 0.93 },
      rug_4 = { x = 1, y = 1 },       -- 新三格素材：按画布 1:1，禁止拉伸
      rug_5 = { x = 1, y = 1 },
    },''')

# 8) _spawn_furn_tpl：地毯隐藏分支放行新 ckey；隐藏循环避开新实例
patch('_spawn_furn_tpl 放行三格地毯',
      '''  if ckey=="rug" or ckey=="rug_2" or ckey=="rug_3" then
    for k,o in pairs(self._furn_inst or {}) do
      if string.find(k,"|rug",1,true) and o and o.SetVisible then pcall(function() o:SetVisible(false) end) end
    end
    return false
  end''',
      '''  if ckey=="rug" or ckey=="rug_2" or ckey=="rug_3" then
    for k,o in pairs(self._furn_inst or {}) do
      if string.find(k,"|rug",1,true)
         and not string.find(k,"|rug_4",1,true)
         and not string.find(k,"|rug_5",1,true)
         and o and o.SetVisible then
        pcall(function() o:SetVisible(false) end)
      end
    end
    return false
  end''')
patch('_spawn_furn_tpl is_rug 纳入新素材',
      '  local is_rug = ckey == "rug" or ckey == "rug_2" or ckey == "rug_3"',
      '  local is_rug = ckey == "rug" or ckey == "rug_2" or ckey == "rug_3"\n'
      '                 or ckey == "rug_4" or ckey == "rug_5"')

# 9) 691 的 _furn_prefab_map 动态读取 things.children 的 referencedPrefabIndex：
#    新增引用控件会带正确的新源 ID，无需再改该函数。

# ── 三格地毯新素材规格（2×2 画布，3 个独立 108×108 格位，零溢出） ──
CELL = 108.0
CANVAS = 216.0
RINGS = [('外框', 108.0, '0xFFB89A62'), ('内面', 82.08, '0xFFDCC684'),
         ('内框', 64.80, '0xFFC9B072')]
# 相对 bbox 左上角的格位 → 画布中心坐标（y 向上为正，2×2 格中心 ±54）
QUAD = {(-54.0, 54.0): '左上', (54.0, 54.0): '右上',
        (-54.0, -54.0): '左下', (54.0, -54.0): '右下'}
L3_SHAPES = {
    'furn.rug.4': dict(variant='L3a', level=3, missing='右下',
                       cells=[(3, 2), (3, 3), (4, 2)],
                       quads=[(-54.0, 54.0), (54.0, 54.0), (-54.0, -54.0)]),
    'furn.rug.5': dict(variant='L3b', level=7, missing='左下',
                       cells=[(2, 3), (2, 4), (3, 4)],
                       quads=[(-54.0, 54.0), (54.0, 54.0), (54.0, -54.0)]),
}


def carpet_layers(quads):
    out = []
    for (x, y) in quads:
        for j, (part, size, color) in enumerate(RINGS, 1):
            out.append(dict(part=part, quad=QUAD[(x, y)], x=x, y=y,
                            w=size, h=size, imageId=100001, color=color,
                            order=len(out) + 1))
    return out


CARPET_SPEC = {}
for tpl, shape in L3_SHAPES.items():
    layers = carpet_layers(shape['quads'])
    CARPET_SPEC[tpl] = dict(
        template=tpl, kind='carpet', variant=shape['variant'], level=shape['level'],
        missing=shape['missing'], cells=[list(c) for c in shape['cells']],
        canvas=dict(W=CANVAS, H=CANVAS, cell=CELL, grid='2×2'),
        layerCount=len(layers), layers=layers,
        gate=dict(zeroSpur=all(abs(l['x']) + l['w'] / 2 <= CANVAS / 2 and
                               abs(l['y']) + l['h'] / 2 <= CANVAS / 2 for l in layers),
                  noStretch=True, legalPrimitives=[100001],
                  layerBudget=len(layers) <= 12, distinctAsset=True),
        referenceRoute=['源记录 (parent=null, 150×150, childList=[content])',
                        '母本记录 (parent=ClientUIPrototypeHierarchyRoot, 150×150)',
                        'things 引用控件 (parent=things, 80×80, referencedPrefabIndex=源ID)',
                        'content (216×216, childList=9 层)',
                        'path_map → cfg.furn_tpl_prefab → cfg.furn_tpl_canvas',
                        'TPL_KEY.carpet.L3a/L3b → furn_tpl → _spawn_furn_tpl',
                        'InstantiateClientUIControl + SetSizeDelta(2格×2格)'])

# ── 家具规格文件（本地调研包映射 + 新素材） ──
FURN = dict(
    localResearchPackage='官网美术素材调研-2026-11-13/',
    researchGap='高频素材-TemplateSpec.json 的 14 组规格只有 7 类，缺 Carpet 独立逐件层表；'
                'globalLayers 只给 49 tile 组合规则。688 的自建规格是 216×108 / 108×216 拉伸版，'
                '本轮按用户要求改为「三格 L 形独立新建素材」。',
    furnitureUsed={str(lv): list(
        {k: v for k, v in (V14D[lv] if lv == 3 else V15D[lv])['objects'].items() if v}.keys())
        for lv in range(3, 8)},
    levelsWithTriCarpet=[3, 7],
    newAssets=CARPET_SPEC,
    unchanged='其余单格/横双/竖双/非连片地毯仍走 691 的逐格 rug_cell_els（未被本轮改动）')

# ── 顺序对照表 ──
MD = ['# 692 · 卡序 / 说话人顺序对照表', '',
      '> 第3关：设计零改动（房间／门／家具／答案站位／谓词集合与 v14 逐字段相同），只重排卡序提高本人自述。',
      '> 第4关：A/D **姓名对调**，卡序、谓词、答案、真假向量全部未动；卡面按新姓名表重渲染，本人一律用「我」。',
      '> 「←原卡N」为 v14 设计图卡槽号，供逐条核对顺序。人名前的字母只加字母、不加分隔符；「我」前不加。', '']
for lv in (3, 4):
    d = D3F if lv == 3 else V15D[4]
    order = d['order_table']
    MD += [f'## 第{lv}关（{d["grid"]}×{d["grid"]}，盗窃者 {d["thief"]}）', '',
           '| 卡槽 | 说话人 | 姓名（存档 who） | 卡面（存档 what） | ←原卡 | 本人自述 |',
           '|---:|:---:|---|---|:---:|:---:|']
    for i, row in enumerate(order):
        if lv == 3:
            what = TEXTS['3'][i]['what']
        else:
            what = TEXTS['4'][i]['what']
        MD.append(f'| {row["slot"]} | {row["speaker"]} | {pref(row["speaker"], FINAL[lv][row["speaker"]])} '
                  f'| {what} | {row["from_slot"]} | '
                  f'{"是" if row["self_narrated"] else "否"} |')
    MD.append('')

OUT = dict(
    version=692,
    base='../691_橙黄通用卡与真机修复/691_橙黄通用卡与真机修复.gil',
    moduleReplacement=dict(name='case_003 整体替换为 v14 定稿',
                           marker='__M["levels.case_003"] = function()',
                           newModule=MODULE3),
    luaPatches=PATCHES,
    prefabPlaceholders=['__RUG4_PREFAB__', '__RUG5_PREFAB__'],
    names={str(k): v for k, v in FINAL.items()},
    namePrefixRule='人名前只加对应字母（如 A值班保安）；「我」等代词前不加；'
                   '作用于 who、Lua suspects/victim.name、what 卡面中的姓名',
    level4NameSwap=dict(A=dict(before=NAMES_BY_LEVEL[4]['A'], after=FINAL[4]['A']),
                        D=dict(before=NAMES_BY_LEVEL[4]['D'], after=FINAL[4]['D']),
                        puzzleChanged=False,
                        note='仅姓名标签与卡面渲染，谓词/卡序/几何/答案/真假向量零改动；28/28 闸门全通过'),
    level3=dict(gates='六卡全真教学关（verify_v14 level==3 口径）',
                legalOrders=len(CANDS), selfNarration=f'{COV}/{TOT3}',
                baseline=f'{BASELINE3}/{TOT3}', order=[i + 1 for i in ORDER3]),
    carpet=L3_SHAPES,
)
(ROOT / '692_设计与补丁.json').write_text(json.dumps(OUT, ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '692_关卡数据.json').write_text(
    json.dumps(dict(version=692, level3=LEVEL3_DATA, names={str(k): v for k, v in FINAL.items()}),
               ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '692_静态文本补丁.json').write_text(
    json.dumps(dict(rule=OUT['namePrefixRule'], texts=TEXTS), ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '692_家具规格.json').write_text(json.dumps(FURN, ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '692_浅蓝提示格.json').write_text(
    json.dumps(dict(rule='线索卡-位置提示表.md §二 + 665/666/691 口径；颜色沿用 0x7F0063D5',
                    levels={'3': LEVEL3_DATA['hints']}), ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '692_顺序对照表.md').write_text('\n'.join(MD), encoding='utf8')

print('Lua 补丁', len(PATCHES), '项；第3关模块', len(MODULE3), '字节；静态文本',
      sum(len(v) for v in TEXTS.values()), '条')
for lv in ('3', '4'):
    print(f'--- 第{lv}关文本 ---')
    for t in TEXTS[lv]:
        print(f"  {t['slot']} {t['letter']} | {t['who']} | {t['what']}")
print('新素材:', list(CARPET_SPEC), '层数', {k: v['layerCount'] for k, v in CARPET_SPEC.items()},
      '零溢出', {k: v['gate']['zeroSpur'] for k, v in CARPET_SPEC.items()})
print('已生成 6 份规格文件')
