"""生成 688 写档所需的全部规格数据（离线，不碰 .gil）。

产出：
  688_关卡数据.json      4 关 Lua table 结构 + 线索类型映射
  688_静态文本.json      逐关逐卡 letter/who/what
  688_家具规格.json      5 类家具调研包映射 + 自建地毯 TemplateSpec（本地调研包缺失项）
  688_浅蓝提示格.json    按历史规则逐卡算出的静态高亮格
  688_顺序对照表.md      用户「只验证顺序」用的对照表
"""
import json, pathlib, re, sys, itertools
sys.stdout.reconfigure(encoding='utf-8')
ROOT = pathlib.Path(__file__).resolve().parent
D = {x['level']: x for x in json.loads((ROOT / 'design_selected_v15.json').read_text(encoding='utf8'))}
LEVELS = (4, 5, 6, 7)
OBJS = ['桌子', '椅子', '书架', '植物', '地毯']
BLOCK = {'桌子', '书架', '植物'}          # 不可站
KIND = {'桌子': 'table', '椅子': 'chair', '书架': 'shelf',
        '植物': 'plant', '地毯': 'carpet'}
PRED = re.compile(
    r'(只有)?([A-FV])(?:(比)([A-FV])靠(上|下)(\d+)行|比([A-FV])靠(左|右)(\d+)列)'
    r'|(?:(比)([A-FV])靠(上|下)(\d+)行|比([A-FV])靠(左|右)(\d+)列)?'
)


def parse_clause(s):
    """中文谓词 → 存档 Lua clue table。方位词用新增「只比轴」类型。"""
    # 只有X在Y上
    m = re.fullmatch(r'只有([A-FV])在(椅子|地毯)上', s)
    if m:
        return dict(type='only_on_object', who=m[1], object=m[2])
    # X在Y上
    m = re.fullmatch(r'([A-FV])在(椅子|地毯)上', s)
    if m:
        return dict(type='on_object', who=m[1], object=m[2])
    # X(不)在Y旁边
    m = re.fullmatch(r'([A-FV])(不在|在)(桌子|椅子|书架|植物|地毯)旁边', s)
    if m:
        return dict(type='not_beside_object' if m[2] == '不在' else 'beside_object',
                    who=m[1], object=m[3])
    # X与Y在同一房间
    m = re.fullmatch(r'([A-FV])与([A-FV])在同一房间', s)
    if m:
        return dict(type='same_room', a=m[1], b=m[2])
    # X比Y靠上/下N行
    m = re.fullmatch(r'([A-FV])比([A-FV])靠(上|下)(\d+)行', s)
    if m:
        return dict(type='row_offset', who=m[1], other=m[2],
                    d=int(m[4]) * (-1 if m[3] == '上' else 1))
    # X比Y靠左/右N列
    m = re.fullmatch(r'([A-FV])比([A-FV])靠(左|右)(\d+)列', s)
    if m:
        return dict(type='col_offset', who=m[1], other=m[2],
                    d=int(m[4]) * (-1 if m[3] == '左' else 1))
    # X在Y上/下/左/右方（只比轴）
    # 687 内嵌 Lua 的 reg("above") 已内建 same_column=false；本轮对
    # below/left_of/right_of 做对称扩展（same_column / same_row = false），
    # 不改默认语义，前两关既有 above/left_of 完全不受影响。
    m = re.fullmatch(r'([A-FV])在([A-FV])(上|下|左|右)方', s)
    if m:
        t = {'上': 'above', '下': 'below', '左': 'left_of', '右': 'right_of'}[m[3]]
        axis = 'same_column' if m[3] in ('上', '下') else 'same_row'
        return dict(type=t, a=m[1], b=m[2], **{axis: False})
    raise ValueError('未识别谓词: ' + s)


def geometry(d):
    n = d['grid']
    room = d['room']
    walls, doors = [], []
    for r in range(n):
        for c in range(n):
            i = r * n + c
            if c + 1 < n and room[i] != room[i + 1]:
                walls.append(['v', r + 1, c + 1])
            if r + 1 < n and room[i] != room[i + n]:
                walls.append(['h', r + 1, c + 1])
    for u, v in d['doors']:
        ru, cu = divmod(u, n)
        rv, cv = divmod(v, n)
        doors.append(['v', ru + 1, min(cu, cv) + 1] if ru == rv
                     else ['h', min(ru, rv) + 1, cu + 1])
    return n, walls, doors


def hint_cells(d, clue):
    """复刻 687 内嵌 Lua 的 hint_for：只认家具自身/四邻、行列、at；其余 nil。"""
    n, walls, doors = geometry(d)
    room = d['room']
    blocked = {v for k in BLOCK for v in d['objects'].get(k, [])}
    objs = d['objects']

    def standable(r, c):
        return 1 <= r <= n and 1 <= c <= n and (r - 1) * n + (c - 1) not in blocked

    def key(r, c):
        return f'{r}:{c}'

    def own(name):
        return [key(*divmod(v, n)[:1] + (0,)) for v in []]  # placeholder, 下方重算
    t = clue['type']
    cells = []
    rule = None
    if t in ('on_object', 'only_on_object', 'one_on_object', 'n_on_object', 'nobody_on_object'):
        for v in objs.get(clue['object'], []):
            r, c = divmod(v, n)
            r, c = r + 1, c + 1
            if standable(r, c):
                cells.append(key(r, c))
        rule = '该家具自己的格子'
    elif t in ('beside_object', 'only_beside', 'not_beside_object'):
        for v in objs.get(clue['object'], []):
            r0, c0 = divmod(v, n)
            for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                r, c = r0 + dr + 1, c0 + dc + 1
                if not standable(r, c):
                    continue
                i = (r - 1) * n + (c - 1)
                j = (r0 * n + c0)
                if room[i] == room[j]:
                    cells.append(key(r, c))
        rule = '该家具四邻、同区域、可站人的格'
    elif t == 'in_col':
        c = clue['c']
        cells = [key(r, c) for r in range(1, n + 1) if standable(r, c)]
        rule = '该列可站格'
    elif t == 'in_row':
        r = clue['r']
        cells = [key(r, c) for c in range(1, n + 1) if standable(r, c)]
        rule = '该行可站格'
    elif t == 'at':
        r, c = clue['r'], clue['c']
        if standable(r, c):
            cells = [key(r, c)]
        rule = '这一格本身'
    else:
        return None                       # 人对人关系 / 区域 / 复合卡：不给提示
    cells = sorted(set(cells), key=lambda s: tuple(map(int, s.split(':'))))
    return dict(rule=rule, count=len(cells), cells=cells)


def build_level(lv):
    d = D[lv]
    n, walls, doors = geometry(d)
    letters = list(d['card_speakers'])
    clues, texts, hints = [], [], []
    for i, card in enumerate(d['cards']):
        parts = [parse_clause(s) for s in card]
        clue = parts[0] if len(parts) == 1 else dict(type='all_of', clauses=parts)
        clues.append(clue)
        texts.append(dict(slot=i + 1, letter=letters[i],
                          who=d['suspects'][letters[i]],
                          what='、'.join(d['archive_texts'][i])))
        # 主线（666/687，即 638 存档所用版本）：复合卡不生成静态高亮。
        # 665 是废案，其「静态位置子句交集」只作为参考值记录，不写入存档行为。
        if clue['type'] == 'all_of':
            sub = [hint_cells(d, p) for p in parts if p['type'] in
                   ('on_object', 'only_on_object', 'beside_object', 'not_beside_object',
                    'in_col', 'in_row', 'at')]
            valid = [x for x in sub if x]
            inter = set(valid[0]['cells']) if valid else set()
            for x in valid[1:]:
                inter &= set(x['cells'])
            hints.append(dict(slot=i + 1, type='all_of', rule='不做位置提示',
                              count=0, cells=[],
                              reference_665=dict(rule='静态位置子句交集',
                                                 count=len(inter),
                                                 cells=sorted(inter)),
                              note='665 为废案；666 与当前主线 687 不给复合卡静态高亮'))
        else:
            h = hint_cells(d, clue)
            hints.append(dict(slot=i + 1, type=clue['type'],
                              rule=h['rule'] if h else '不做位置提示',
                              count=h['count'] if h else 0,
                              cells=h['cells'] if h else []))
    objects = {}
    for name in OBJS:
        cells = d['objects'].get(name, [])
        if not cells:
            continue
        objects[name] = dict(
            cells=[dict(r=v // n + 1, c=v % n + 1) for v in cells],
            occupiable=name not in BLOCK, kind=KIND[name])
    size = dict(rows=n, cols=n)
    suspects = [dict(id=k, name=d['suspects'][k], portrait='portrait.' + k,
                     **({'is_victim': True} if k == 'V' else {})) for k in letters]
    solution = {k: dict(r=v // n + 1, c=v % n + 1)
                for k, v in zip(letters, d['target'])}
    false_slot = letters.index(d['thief']) + 1
    # 浅蓝提示的静态验收清单：引擎仍按 Core:clue_hint 运行时现算（历史规则），
    # 此处只作为写入存档的只读元数据，供逐格比对，不参与任何求值。
    hint_preview = {str(h['slot']): dict(rule=h['rule'], cells=h['cells'],
                                        count=h['count']) for h in hints}
    lua = dict(
        hint_preview=hint_preview,
        id=f'case_{lv:03d}', name=f'案件 {lv:03d} · {d["theme_note"]}',
        difficulty='hard' if lv in (5, 7) else 'normal',
        size=size, room_names=[f'R{i}' for i in range(1, 5)],
        rules=dict(one_per_row=True, one_per_col=True, one_per_room=False,
                   place_all=True, tie_policy='forbid'),
        walls=walls, doors=doors, objects=objects, blocked=[], water=[],
        suspects=suspects, victim=dict(id='V', name=d['suspects']['V']),
        roles=dict(thief=d['thief']), clues=clues, general_clues={},
        meta=dict(announce='unknown', false_clue=false_slot), solution=solution,
        visual_theme=d['visual_theme'],
    )
    return dict(level=lv, lua=lua, texts=texts, hints=hints,
                clue_predicates=d['cards'], order_table=d['order_table'])


def carpet_spec():
    """自建：本地调研包缺 Carpet 独立 TemplateSpec。
    依据《家具几何分解.md》§6 四圈结构 + 调研包 globalLayers 地毯 tile 规则 +
    palettes.variant 色板 + 合法图元 100001 矩形；零溢出闸门。"""
    P = dict(CARPET='#D9C08A', EDGE='#5A4634', GOLD='#C9A961',
             SEAL='#A8391B', PAPER='#EFE4CE', TAG='#7A8FA0')
    out = {}
    for key, W, H, label in [('rug', 108.0, 108.0, '单格'),
                             ('rug.2', 216.0, 108.0, '横向双格'),
                             ('rug.3', 108.0, 216.0, '纵向双格')]:
        # 4 圈同心矩形，归一化尺寸按《家具几何分解》§6；全部 ⊆ 画布（零溢出）
        rings = [(1.000, '#FF' + P['EDGE'][1:], '外框'),
                 (0.933, '#FF' + P['CARPET'][1:], '第二圈'),
                 (0.782, '#FF' + P['GOLD'][1:], '第三圈'),
                 (0.707, '#FF' + P['PAPER'][1:], '内芯')]
        layers = []
        for j, (ratio, color, part) in enumerate(rings, 1):
            w, h = W * ratio, H * ratio
            layers.append(dict(order=j, part=part, imageId=100001, shape='rect',
                               w=round(w, 2), h=round(h, 2), dx=0.0, dy_down=0.0,
                               y_up=0.0, rotDeg=0, color=color, decor=False,
                               note='地毯四圈结构，四圈同心 ⊆ 画布'))
        # 差异化装饰：骑缝章（火漆红小方块）+ 证物标签，均 ⊆ 内芯（零溢出）
        for j, (part, color, w, h, dx, dy) in enumerate([
                ('seal', '#FF' + P['SEAL'][1:], 12.0, 12.0, -W * 0.18, -H * 0.18),
                ('tag', '#FF' + P['TAG'][1:], 20.0, 8.0, W * 0.18, -H * 0.18)], len(layers) + 1):
            layers.append(dict(order=j, part=part, imageId=100001, shape='rect',
                               w=w, h=h, dx=round(dx, 2), dy_down=round(dy, 2),
                               y_up=round(-dy, 2), rotDeg=0, color=color, decor=True,
                               note='差异化装饰层 ⊆ 内芯'))
        out[key] = dict(template='furn.' + key, kind='carpet', variant=label,
                        sizePx=dict(W=W, H=H), layerCount=len(layers),
                        canvas=dict(cell=108.0, W=W, H=H), layers=layers,
                        gate=dict(zeroSpur=True, decorWithinCore=True,
                                  legalPrimitives=[100001], layerBudget=len(layers) <= 12))
    return dict(
        title='自建 · 地毯 Carpet 图元拆解规格（补齐本地调研包缺失）',
        reason='官网美术素材调研-2026-11-13/assets 仅有 7 套高频 TemplateSpec，'
               '不含 Carpet；globalLayers 只给 49 tile 组合规则，无逐件层表。',
        source=['官网美术素材调研-2026-11-13/高频素材-图元拆解规格.json',
                '官网美术素材调研-2026-11-13/高频素材-TemplateSpec.json',
                '_work/art-ref/家具几何分解.md §6',
                'qianxing-murdoku/lua/furn_art.lua（furn.rug/.2/.3 现有模板）'],
        localTemplatesAlreadyInGil=['furn.rug', 'furn.rug.2', 'furn.rug.3'],
        occupiable=True, officialId=5, officialName='Carpet',
        differentiatedName='档案纸地毯 · 骑缝章',
        spec=out)


def main():
    levels = [build_level(lv) for lv in LEVELS]
    (ROOT / '688_关卡数据.json').write_text(
        json.dumps(dict(version='688', levels=levels), ensure_ascii=False, indent=2), encoding='utf8')
    (ROOT / '688_静态文本.json').write_text(
        json.dumps({str(x['level']): x['texts'] for x in levels}, ensure_ascii=False, indent=2), encoding='utf8')
    (ROOT / '688_浅蓝提示格.json').write_text(
        json.dumps(dict(rule='线索卡-位置提示表.md §二 + 665 变更与验收「浅蓝提示」；'
                             '颜色沿用 0x7F0063D5，hint 控件已在 687 存档中',
                        levels={str(x['level']): x['hints'] for x in levels}),
                   ensure_ascii=False, indent=2), encoding='utf8')
    (ROOT / '688_家具规格.json').write_text(
        json.dumps(dict(
            localResearchPackage='官网美术素材调研-2026-11-13/',
            furnitureUsed={str(x['level']): list(x['lua']['objects']) for x in levels},
            assetMapping={str(lv): D[lv]['asset_mapping'] for lv in LEVELS},
            carpetSelfBuilt=carpet_spec()), ensure_ascii=False, indent=2), encoding='utf8')
    # 顺序对照表（用户「只验证顺序」）
    md = ['# 688 · 第4/5/6/7关 卡序 / 说话人顺序对照表', '',
          '> 设计零改动：房间、门、家具、答案站位、盗窃者身份、谓词集合与 v14 逐字段相同；',
          '> 仅重排卡片归属顺序，使本人相关线索尽可能由本人自述。',
          '> 括号「←原卡N」为 v14 设计图中的卡槽号，供逐条核对顺序。', '']
    for lv in LEVELS:
        d = D[lv]
        md += [f'## 第{lv}关（{d["grid"]}×{d["grid"]}，盗窃者 {d["thief"]}）', '',
               '| 卡槽 | 说话人 | 姓名 | 卡面（写入存档） | ←原卡 | 本人自述 |',
               '|---:|:---:|---|---|:---:|:---:|']
        for r in d['order_table']:
            md.append(f'| {r["slot"]} | {r["speaker"]} | {r["name"]} | '
                      f'{"、".join(r["archive_text"])} | {r["from_slot"]} | '
                      f'{"是" if r["self_narrated"] else "否"} |')
        md.append('')
    (ROOT / '688_顺序对照表.md').write_text('\n'.join(md), encoding='utf8')
    for x in levels:
        hs = x['hints']
        print(f"第{x['level']}关 卡{len(x['texts'])}张 "
              f"有提示{sum(1 for h in hs if h['count'] > 0)}张 "
              f"提示格总数{sum(h['count'] for h in hs)} "
              f"线索类型{sorted(set(h['type'] for h in hs))}")
    print('已生成 5 份规格文件')


if __name__ == '__main__':
    main()
