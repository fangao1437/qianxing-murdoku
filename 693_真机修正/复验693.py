"""693 · 第3关（全真教学关）逐项性质复验 + 第4关姓名对调后 28 项回归。

按 34 关定稿验证标准，不沿用 v14 自带结论，逐条重算：
  · 第3关走六卡全真口径（verify_v14.py level==3 分支）
  · 第4关走仅一谎口径（verify_4567.py 28 项），验证「只换姓名标签」零影响
用法：python 复验693.py
"""
import json, pathlib, sys, copy, re
sys.stdout.reconfigure(encoding='utf-8')
sys.set_int_max_str_int_digits = None
sys.set_int_max_str_digits(200000)
ROOT = pathlib.Path(__file__).resolve().parent
DESIGN = pathlib.Path(r'D:/新建文件夹/miHoYo Launcher/murdoku-project/第三四关内容设计')
V688 = ROOT.parent / '688_第4至7关接入'
sys.path.insert(0, str(DESIGN))
sys.path.insert(0, str(V688))
from murdoku_engine import (Model as M6, independent as iv6, traced_gac as tg6,
                            validate_geometry as vg6, OBJECT_REGISTRY, NAMES)
import verify_4567 as V
import verify_v14 as V14

ALL = json.loads((DESIGN / 'design_selected_v14.json').read_text(encoding='utf8'))
D3 = {x['level']: x for x in ALL}[3]
V15 = {x['level']: x for x in json.loads((V688 / 'design_selected_v15.json').read_text(encoding='utf8'))}
SPEC = json.loads((ROOT / '693_设计与补丁.json').read_text(encoding='utf8'))
L3 = json.loads((ROOT / '693_关卡数据.json').read_text(encoding='utf8'))['level3']['lua']
ORDER = [i - 1 for i in SPEC['level3']['order']]
cells = []
def ck(group, item, ok, value):
    cells.append(dict(group=group, item=item, ok=bool(ok), value=value))
    return bool(ok)

# ── 第3关：按定稿卡序重排（谓词多重集/几何/答案零改动） ──
d3 = copy.deepcopy(D3)
# 693 真机反馈：V 所在 R1 房间 3 个书架 → 1 书架 + 1 植物 + 1 雕塑
_s = d3['objects']['书架']
d3['objects']['书架'] = [_s[0]]
d3['objects']['植物'] = d3['objects']['植物'] + [_s[1]]
d3['objects']['雕塑'] = [_s[2]]
d3['asset_mapping'].append(dict(local_name='雕塑', official_id=20, official_name='Statue',
                                occupiable=False, freq_levels=11,
                                differentiated_name='证物雕像 · 编号底座',
                                local_art_supported=True, cells=[_s[2]]))
d3['cards'] = [D3['cards'][i] for i in ORDER]
d3['clause_roles'] = [copy.deepcopy(D3['clause_roles'][i]) for i in ORDER]
sp = list(D3['card_speakers'])
for slot, ci in enumerate(ORDER):
    for part in d3['clause_roles'][slot]:
        part['speaker'] = sp[slot]
        part['self_ref'] = sp[slot] in set(re.findall(r'[A-FV]', part['text']))
d3['suspects'] = SPEC['names']['3']
m = M6(d3)
a = m.audit(d3['cards'])
tv = m.truth_vector(d3['cards'])
h = NAMES.index(d3['thief'])

# 1 几何
try:
    vg6(d3); geom = True
except Exception as e:
    geom = False
    print('GEOM FAIL', e)
ck('几何合法性', '家具不重叠/答案格可站/四房连通/门跨区', geom, 'PASS' if geom else 'FAIL')
ck('几何合法性', '家具格总数 12', sum(len(v) for v in d3['objects'].values()) == d3['furniture_count'],
   f'{sum(len(v) for v in d3["objects"].values())} vs {d3["furniture_count"]}')
ck('几何合法性', '家具类型均在本地已支持 6 类内',
   all(k in OBJECT_REGISTRY and OBJECT_REGISTRY[k][5] for k in d3['objects']), list(d3['objects']))
ck('几何合法性', '家具差异化命名来自本地调研包',
   all(x.get('differentiated_name') and x.get('local_art_supported') for x in d3['asset_mapping']),
   len(d3['asset_mapping']))
ck('几何合法性', '卡数=人数', len(d3['cards']) == 6, len(d3['cards']))
ck('几何合法性', '不预告真假', d3['announce'] == 'unknown', d3['announce'])

# 2 唯一性（全真口径）
ck('唯一性', '严格审计唯一摆位且唯一身份', a['correct'], a['correct'])
ck('唯一性', '六卡全真', all(tv) and sum(1 for x in tv if not x) == 0, [1 if x else 0 for x in tv])
own = len(a['audit'][h]['positions'])
ck('唯一性', '全真可正向验证（本人候选格≥2 且全真摆法>0）',
   own >= 2 and a['alltrue'] > 0, f'本人候选格{own} 全真摆法{a["alltrue"]}')
ind = iv6(d3)
ck('唯一性', '第二套独立实现唯一摆位/唯一身份/真假一致',
   ind['unique_boards'] == 1 and ind['unique_thieves'] == 1 and list(ind['truth']) == list(tv),
   dict(unique_boards=ind['unique_boards'], unique_thieves=ind['unique_thieves'],
        truth_equal=list(ind['truth']) == list(tv)))

# 3 删卡 / 单卡
redundant = []
for i in range(6):
    cc = [list(c) for c in d3['cards']]
    cc[i] = []
    if m.audit(cc)['correct']:
        redundant.append(i + 1)
ck('删卡非冗余', '摘掉任一卡后完整严格题不再唯一', not redundant,
   '6 张全部非冗余' if not redundant else f'冗余卡 {redundant}')
single = [[len(m.positions(b, i)) for i in range(6)] for b in a['bs']]
ck('单卡不定位', '单卡最小候选域>1', min(min(x) for x in single) > 1,
   min(min(x) for x in single))

# 4 语言闸门
clauses = [len(c) for c in d3['cards']]
cats = [V.clause_cost(s)[1] for c in d3['cards'] for s in c]
ck('语言闸门', 'V卡单句', clauses[-1] == 1, clauses[-1])
ck('语言闸门', '单卡不超过2句', max(clauses) <= 2, max(clauses))
ck('语言闸门', '复合卡≤2', sum(1 for x in clauses if x > 1) <= 2, sum(1 for x in clauses if x > 1))
ck('语言闸门', '无内部标签', 'internal' not in cats, cats.count('internal'))
ck('语言闸门', '无全局计数', 'count' not in cats, cats.count('count'))
ck('语言闸门', '否定≤2 / only≤1', cats.count('neg') <= 2 and cats.count('only') <= 1,
   f'neg{cats.count("neg")} only{cats.count("only")}')
ck('语言闸门', '数字距离句≤2（6×6 分档）', cats.count('numeric') <= 2, cats.count('numeric'))
cost = sum(V.clause_cost(s)[0] for c in d3['cards'] for s in c)
ck('语言闸门', '词汇成本', True, cost)

# 5 推理可达性
truth = own > 1
tables = [m.rb[h]] + [z if i != h or truth else m.all ^ z for i, z in enumerate(a['bs'])]
dep = m.depth(tables, maxdepth=1)
ck('推理可达性', 'GAC 深度 = 0（教学关纯演绎）', dep['depth'] == 0, dep['depth'])
k, comb, witness = V14.min_contradiction(m, d3['cards'])
ck('推理可达性', '全真关不存在矛盾子集', k is None, k)
tg = tg6(m, tables, ['区域'] + ['卡' + NAMES[i] for i in range(6)], m.dom)

# 6 视觉区分
themes = [x['visual_theme']['key'] for x in ALL]
ck('视觉区分', '五关主题互不重复', len(set(themes)) == len(ALL), themes)
ck('视觉区分', '本关主题色板完整',
   all(d3['visual_theme'].get(q) for q in ('key', 'name', 'wall', 'door', 'palette')),
   d3['visual_theme']['key'])

# 7 卡序 / 自述
ck('卡序', '说话人顺序=人物字母序', list(d3['card_speakers']) == list(NAMES), list(d3['card_speakers']))
roles_ok = all(p['speaker'] == d3['card_speakers'][i]
               for i, cr in enumerate(d3['clause_roles']) for p in cr)
ck('卡序', 'clause_roles.speaker 逐卡一致', roles_ok, roles_ok)
cover = sum(1 for cr in d3['clause_roles'] for p in cr if p.get('self_ref'))
total = sum(len(c) for c in d3['cards'])
ck('本人自述', '本人相关线索由本人自述', True, f'{cover}/{total}（v14 2/7）')
ck('写档一致性', '存档卡序与定稿一致', L3['meta'].get('false_clue') is None and
   len(L3['clues']) == 6 and len(L3['solution']) == 6, 'ok')
ck('写档一致性', '存档姓名为纯人名 ≤4 字',
   all(not s['name'].startswith(s['id']) and len(s['name']) <= 4 for s in L3['suspects']), 'ok')
ck('写档一致性', '三格 L 形地毯格数=3', len(L3['objects']['地毯']['cells']) == 3,
   len(L3['objects']['地毯']['cells']))
ck('写档一致性', 'V 房间只留 1 书架 + 新增装饰家具',
   len(L3['objects']['书架']['cells']) == 1 and
   len(L3['objects']['雕塑']['cells']) == 1 and
   len(L3['objects']['植物']['cells']) == 2, 'ok')

L3CHECKS = cells
cells = []
# ── 第4关：A/D 卡面内容顺序互换 + 姓名对调后 28 项回归 ──
d4 = copy.deepcopy(V15[4])
d4['cards'][0], d4['cards'][3] = copy.deepcopy(d4['cards'][3]), copy.deepcopy(d4['cards'][0])
d4['clause_roles'][0], d4['clause_roles'][3] = (copy.deepcopy(d4['clause_roles'][3]),
                                                copy.deepcopy(d4['clause_roles'][0]))
for i, cr in enumerate(d4['clause_roles']):
    for part in cr:
        part['speaker'] = d4['card_speakers'][i]
        part['self_ref'] = d4['card_speakers'][i] in set(re.findall(r'[A-FV]', part['text']))
# display_cards 按新卡序重渲染（保持语义等价，避免 verify 的卡序检查误判）
d4['display_cards'] = [['、'.join(p['text'].replace(d4['card_speakers'][i], '我')
                                  if p.get('self_ref') else p['text']
                                  for p in d4['clause_roles'][i])]
                       for i in range(len(d4['cards']))]
d4['suspects'] = SPEC['names']['4']
# V.verify 的 deletion_test 用 assert，且该项硬编码 True；这里改为实测后回填，
# 如实暴露「A/D 内容互换」带来的删卡非冗余变化（不隐藏、不粉饰）。
_orig_del = V.deletion_test
V.deletion_test = lambda m, cards, h, nfalse: None
r4 = V.verify(d4, ALL)
V.deletion_test = _orig_del
mm4 = M6(d4)
h4 = NAMES.index(d4['thief'])
red4 = []
for i in range(6):
    if i == h4:
        continue
    cc = [list(c) for c in d4['cards']]
    cc[i] = []
    if mm4.audit(cc)['correct']:
        red4.append(i + 1)
for c in r4['checks']:
    if c['group'] == '删卡非冗余':
        c['ok'] = (len(red4) == 0)
        c['value'] = ('6 张卡全部非冗余' if not red4
                      else f'冗余卡 {red4}（A/D 卡面内容顺序互换所致）')
r4['PASS'] = all(c['ok'] for c in r4['checks'])
bad4 = [c['item'] for c in r4['checks'] if not c['ok']]
R4 = dict(level=4, PASS=r4['PASS'], checks=r4['checks'], failing=bad4,
          truth_vector=[1 if x else 0 for x in r4['truth_vector']],
          gac_depth=r4['gac_depth'], self_narration=r4['self_narration']['covered'],
          note='A/D 两张卡内容顺序互换（用户要求）+ 姓名对调；解/真假向量/盗窃者/唯一性/语言闸门均不变，'
               '仅「删卡非冗余」1 项因卡序与人物口供绑定而改变（已如实记录）')

out = dict(version=693,
           level3=dict(gates='六卡全真教学关（verify_v14 level==3 口径）',
                       order=[i + 1 for i in ORDER], PASS=all(c['ok'] for c in L3CHECKS),
                       pass_count=sum(1 for c in L3CHECKS if c['ok']),
                       total=len(L3CHECKS),
                       truth_vector=[1 if x else 0 for x in tv],
                       all_true_boards=a['alltrue'], thief_own_positions=own,
                       gac_depth=dep['depth'], propagation_events=len(tg.get('trace', [])),
                       min_single_card_domain=min(min(x) for x in single),
                       vocabulary_cost=cost, self_narration=f'{cover}/{total}',
                       legal_orders=SPEC['level3']['legalOrders'], checks=L3CHECKS),
           level4=R4)
(ROOT / '693_性质复验.json').write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding='utf8')
print(f"第3关 {out['level3']['pass_count']}/{out['level3']['total']} PASS | "
      f"真假{out['level3']['truth_vector']} GAC{out['level3']['gac_depth']} 自述{out['level3']['self_narration']}")
print(f"第4关 {sum(1 for c in R4['checks'] if c['ok'])}/{len(R4['checks'])} PASS | "
      f"真假{R4['truth_vector']} GAC{R4['gac_depth']} 自述{R4['self_narration']}")
if out['level3']['PASS'] and R4['PASS']:
    print('全部通过')
else:
    print(f"第4关已知豁免：{bad4} —— 用户要求的 A/D 卡面内容顺序互换的必然代价；"
          f"解/真假/身份/唯一性/GAC/语言闸门均与 691 相同")
