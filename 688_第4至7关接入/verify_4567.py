"""第4/5/6/7关 v14 设计图 · 按第3/4关定稿验证标准逐项独立复验（v15）。

与 verify_v14.py 的区别：不沿用 v14 自带的结论，而是把 34 关定稿时使用的
「各项性质」逐条重新计算，并按各关既定难度带设定闸门；额外检查视觉区分、
家具调研规格、卡序/说话人/本人自述一致性。

用法：python verify_4567.py <design.json> <out.json>
"""
import sys, json, pathlib, re, itertools
sys.set_int_max_str_digits(200000)
ROOT = pathlib.Path(r'D:/新建文件夹/miHoYo Launcher/murdoku-project/第三四关内容设计')
sys.path.insert(0, str(ROOT))
from murdoku_engine import (Model as M6, independent as iv6, traced_gac as tg6,
                            validate_geometry as vg6, OBJECT_REGISTRY, NAMES, OCCUPY)
from murdoku_engine_generic import (Model as M7, independent as iv7,
                                   traced_gac as tg7, validate_geometry as vg7, names_of)

NUMERIC = re.compile(r'比')
INTERNAL = re.compile(r'在R\d+房间|在第\d+(行|列)')
COUNT = re.compile(r'上有\d+人')


def clause_cost(s):
    if NUMERIC.search(s): return 3, 'numeric'
    if '不在' in s: return 2, 'neg'
    if COUNT.search(s): return 2, 'count'
    if s.startswith('只有'): return 2, 'only'
    if '独自在房间' in s: return 2, 'alone'
    if INTERNAL.search(s): return 1, 'internal'
    if '旁边' in s: return 1, 'beside'
    if '同一房间' in s or s.endswith('方'): return 1, 'rel'
    return 1, 'on'


def min_contradiction(m, cards):
    bs = [m.card(c) for c in cards]
    for k in range(2, m.n + 1):
        for comb in itertools.combinations(range(m.n), k):
            z = m.all
            for i in comb:
                z &= bs[i]
                if z == 0: break
            if z == 0:
                return k, [cards[i] for i in comb]
    return None, []


def deletion_test(m, cards, h, nfalse):
    out = []
    for i in range(m.n):
        if nfalse and i == h:
            out.append(dict(card=i, skipped=True, reason='假卡由其余真卡联合否证'))
            continue
        cc = [list(c) for c in cards]
        cc[i] = []
        a2 = m.audit(cc)
        assert not a2['correct'], f'第{i}张真卡冗余（摘掉后严格题仍唯一）'
        out.append(dict(card=i, contributes=True))
    return out


def self_coverage(d):
    """本人自述覆盖率：以「子句」为单位，统计已改写成「我」的自指子句数。"""
    total = cover = 0
    detail = []
    for i, card in enumerate(d['cards']):
        sp = d['card_speakers'][i]
        joined = '、'.join(d['display_cards'][i])
        for j, s in enumerate(card):
            total += 1
            hit = d['clause_roles'][i][j].get('self_ref', False)
            cover += bool(hit)
            detail.append(dict(card=i, clause=j, speaker=sp, predicate=s,
                               display=joined, self_narrated=bool(hit)))
    return cover, total, detail


def verify(d, all_levels):
    lv, n = d['level'], len(d['target'])
    is7 = (n == 7)
    M, iv, tg, vg = (M7, iv7, tg7, vg7) if is7 else (M6, iv6, tg6, vg6)
    na = names_of(n) if is7 else NAMES
    rows = []

    def chk(group, name, ok, value):
        rows.append(dict(group=group, item=name, ok=bool(ok), value=value))
        return bool(ok)

    # 1 几何与静态规格
    try:
        vg(d); geom = True
    except Exception as e:
        geom = False
        print('GEOM FAIL', lv, e)
    chk('几何合法性', '家具不重叠/答案格可站/四房连通/门跨区', geom, 'PASS' if geom else 'FAIL')
    cells = sum(d['objects'].values(), [])
    chk('几何合法性', '家具格总数', len(cells) == d['furniture_count'],
        f'{len(cells)} vs {d["furniture_count"]}')
    chk('几何合法性', '家具类型均在本地已支持6类内',
        all(k in OBJECT_REGISTRY and OBJECT_REGISTRY[k][5] for k in d['objects']),
        list(d['objects']))
    chk('几何合法性', '家具差异化命名来自本地调研包',
        all(a.get('differentiated_name') and a.get('local_art_supported')
            for a in d['asset_mapping']), len(d['asset_mapping']))
    chk('几何合法性', '卡数=人数', len(d['cards']) == n, f'{len(d["cards"])}/{n}')
    chk('几何合法性', '不预告真假', d['announce'] == 'unknown', d['announce'])

    # 2 严格审计 + 双实现
    m = M(d)
    a = m.audit(d['cards'])
    chk('唯一性', '严格审计唯一摆位且唯一身份', a['correct'], a['correct'])
    tv = m.truth_vector(d['cards'])
    h = na.index(d['thief'])
    own = len(a['audit'][h]['positions'])
    nfalse = sum(1 for x in tv if not x)
    chk('唯一性', '仅盗窃者卡为假', nfalse == 1 and not tv[h], f'假卡数{nfalse} 盗窃者{na[h]}')
    chk('唯一性', '谎言被其余真卡联合否证', own == 1 and a['alltrue'] == 0,
        f'本人候选格{own} 全真摆法{a["alltrue"]}')
    chk('唯一性', '第二套独立实现唯一摆位/唯一身份/真假一致',
        True, '见 independent 字段')  # 值在下方单独记录
    ind = iv(d, boards=m.x) if is7 else iv(d)
    rows[-1]['ok'] = (ind['unique_boards'] == 1 and ind['unique_thieves'] == 1
                      and list(ind['truth']) == list(tv))
    rows[-1]['value'] = {'unique_boards': ind['unique_boards'],
                         'unique_thieves': ind['unique_thieves'],
                         'truth_equal': list(ind['truth']) == list(tv)}

    # 3 删卡 / 单卡
    deletion_test(m, d['cards'], h, nfalse)
    chk('删卡非冗余', '摘掉任一真卡后完整严格题不再唯一', True, f'{n-1}张真卡全部非冗余')
    bs = a['bs']
    single = [[len(m.positions(b, i)) for i in range(n)] for b in bs]
    chk('单卡不定位', '单卡最小候选域>1', min(min(x) for x in single) > 1,
        min(min(x) for x in single))

    # 4 语言闸门（按各关既定难度带）
    clauses = [len(c) for c in d['cards']]
    ncomp = sum(1 for x in clauses if x > 1)
    cats = [clause_cost(s)[1] for c in d['cards'] for s in c]
    chk('语言闸门', 'V卡单句', clauses[-1] == 1, clauses[-1])
    chk('语言闸门', '单卡不超过2句', max(clauses) <= 2, max(clauses))
    chk('语言闸门', '复合卡≤2', ncomp <= 2, ncomp)
    chk('语言闸门', '无内部标签', 'internal' not in cats, cats.count('internal'))
    chk('语言闸门', '无全局计数', 'count' not in cats, cats.count('count'))
    neg, only, numeric = cats.count('neg'), cats.count('only'), cats.count('numeric')
    chk('语言闸门', '否定≤2 / only≤1', neg <= 2 and only <= 1, f'neg{neg} only{only}')
    chk('语言闸门', f'数字距离句≤{3 if is7 else 2}（按盘面分档）',
        numeric <= (3 if is7 else 2), numeric)
    cost = sum(clause_cost(s)[0] for c in d['cards'] for s in c)
    chk('语言闸门', '词汇成本', True, cost)

    # 5 GAC 深度
    truth = own > 1
    tables = [m.rb[h]] + [z if i != h or truth else m.all ^ z for i, z in enumerate(bs)]
    want_depth = 1 if lv in (5, 7) else 0
    dep = m.depth(tables, maxdepth=1)
    chk('推理可达性', f'GAC深度={want_depth}（难度带 Medium-Hard 保留一次试位）',
        dep['depth'] == want_depth, dep['depth'])
    tr = tg(m, tables, ['区域'] + ['卡' + na[i] for i in range(n)], m.dom)
    k, witness = min_contradiction(m, d['cards'])
    chk('谎言可察', '存在最小矛盾子集', k is not None, k)

    # 6 视觉区分
    themes = [x['visual_theme']['key'] for x in all_levels]
    chk('视觉区分', '五关主题互不重复', len(set(themes)) == len(all_levels), themes)
    chk('视觉区分', '本关主题色板完整',
        all(d['visual_theme'].get(q) for q in ('key', 'name', 'wall', 'door', 'palette')),
        d['visual_theme']['key'])

    # 7 卡序 / 说话人 / 本人自述
    chk('卡序', '说话人顺序=人物字母序（不洗牌、不交叉分配）',
        list(d['card_speakers']) == list(na), list(d['card_speakers']))
    roles_ok = all(part['speaker'] == d['card_speakers'][i]
                   for i, cr in enumerate(d['clause_roles']) for part in cr)
    chk('卡序', 'clause_roles.speaker 与 card_speakers 逐卡一致', roles_ok, roles_ok)
    disp_ok = True
    disp_detail = []
    for i, cr in enumerate(d['clause_roles']):
        sp = d['card_speakers'][i]
        expect = '、'.join(p['text'].replace(sp, '我') if p.get('self_ref') else p['text']
                          for p in cr)
        got = '、'.join(d['display_cards'][i])
        if got != expect:
            disp_ok = False
            disp_detail.append(dict(card=i, expect=expect, got=got))
    chk('卡序', 'display_cards 由 cards 按自指规则生成（语义等价）', disp_ok,
        disp_ok or disp_detail)
    cover, total, sd = self_coverage(d)
    chk('本人自述', '本人相关线索由本人自述（覆盖率，越高越好）', True, f'{cover}/{total}')

    ok = all(r['ok'] for r in rows)
    return dict(level=lv, grid=n, thief=d['thief'], PASS=ok,
                truth_vector=list(tv), unique_boards=ind['unique_boards'],
                unique_thieves=ind['unique_thieves'],
                identity_hypotheses=sum(1 for z in a['audit'] if z['boards'] > 0),
                gac_depth=dep['depth'], propagation_events=len(tr.get('trace', [])),
                contradiction_min_subset=k, contradiction_cards=witness,
                all_true_boards=a['alltrue'], thief_own_positions=own,
                min_single_card_domain=min(min(x) for x in single),
                compound_cards=ncomp, numeric_clauses=numeric,
                negative_clauses=neg, only_clauses=only, vocabulary_cost=cost,
                categories=cats, card_clauses=clauses,
                self_narration=dict(covered=cover, total=total, detail=sd),
                visual_theme=d['visual_theme']['key'],
                objects=d['objects'], target=d['target'], doors=d['doors'],
                checks=rows)


def main():
    src = pathlib.Path(sys.argv[1]); dst = pathlib.Path(sys.argv[2])
    data = json.loads(src.read_text(encoding='utf8'))
    # 第3关是「六卡全真」教学关，仅作 34 关验证标准的来源与视觉主题参照，
    # 不在本轮 4/5/6/7 关的验证范围内（其全真性质与「仅一谎」闸门不相容）。
    out = [verify(d, data) for d in data if d['level'] in (4, 5, 6, 7)]
    dst.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding='utf8')
    for r in out:
        bad = [c['item'] for c in r['checks'] if not c['ok']]
        print(f"第{r['level']}关 {r['grid']}x{r['grid']} | {'PASS' if r['PASS'] else 'FAIL'} | "
              f"身份{r['thief']} 真假{r['truth_vector']} GAC{r['gac_depth']} "
              f"矛盾子集{r['contradiction_min_subset']} 自述{r['self_narration']['covered']}/"
              f"{r['self_narration']['total']} | 检查{len(r['checks'])}项 失败{len(bad)}")
        for b in bad: print('   FAIL:', b)
    print('全部通过' if all(x['PASS'] for x in out) else '存在不合规项')


if __name__ == '__main__':
    main()
