"""第4/5/6/7关 v15 定稿：人物命名 + 本人自述（只调卡序，不动设计）+ 写档用文案。

口径（沿用 665「本人线索」/666「线索换位」历史）：
  · 设计零改动：room/doors/objects/target/thief/谓词集合全部不变，只重排卡序。
  · 严格审计按「第 h 张卡 = 人物 h 的口供」摘卡，故卡序与身份绑定；
    每个候选顺序都要重新跑完整闸门，只保留 28 项全通过者。
  · 固定约束：假卡停在盗窃者卡槽；V 卡槽单句。
  · 每关输出顺序对照表，供用户「只验证顺序」。
用法：python build_v15.py
"""
import json, pathlib, re, itertools, sys, copy
sys.stdout.reconfigure(encoding='utf-8')
sys.set_int_max_str_digits(200000)
ROOT = pathlib.Path(__file__).resolve().parent
SRC = pathlib.Path(r'D:/新建文件夹/miHoYo Launcher/murdoku-project/第三四关内容设计/design_selected_v14.json')
ENG = pathlib.Path(r'D:/新建文件夹/miHoYo Launcher/murdoku-project/第三四关内容设计')
sys.path.insert(0, str(ENG))
from murdoku_engine import Model as M6
from murdoku_engine_generic import Model as M7, names_of

NAMES = {
    4: dict(A='卷宗管理员', B='米纸誊录员', C='页角修复师', D='夜巡值守',
            E='借阅登记员', V='老馆长'),
    5: dict(A='封条保管员', B='夜勘记录员', C='火漆验印师', D='暗房洗印员',
            E='证物登记员', V='守夜馆人'),
    6: dict(A='晒图学徒', B='靛青描图员', C='野外测绘员', D='朱批校样员',
            E='蓝图管理员', F='工地放样员', V='总测绘师'),
    7: dict(A='铜钥保管员', B='转架管理员', C='墨绿誊写员', D='铜牌登记员',
            E='线装匠人', V='藏卷人'),
}
LEVEL_NOTE = {
    4: '档案卷宗 · 米纸浅色', 5: '夜勘卷宗 · 深棕墨/火漆红',
    6: '蓝晒图 · 靛青网格/朱红批注', 7: '旋转档案 · 深墨绿/铜金',
}


def letters_in(s):
    return set(re.findall(r'[A-FV]', s))


def passes(m, cards, d, speakers):
    """位集闸门：严格审计 / 真假向量 / 删卡非冗余 / 单卡不定位 / 语言 / 矛盾。"""
    n = len(cards)
    h = speakers.index(d['thief'])
    a = m.audit(cards)
    if not a['correct']:
        return False
    tv = m.truth_vector(cards)
    if sum(1 for x in tv if not x) != 1 or tv[h]:
        return False
    own = len(a['audit'][h]['positions'])
    if own != 1 or a['alltrue'] != 0:
        return False
    # 删卡非冗余（假卡跳过）
    for i in range(n):
        if i == h:
            continue
        cc = [list(c) for c in cards]
        cc[i] = []
        if m.audit(cc)['correct']:
            return False
    single = [[len(m.positions(b, i)) for i in range(n)] for b in a['bs']]
    if min(min(x) for x in single) <= 1:
        return False
    clauses = [len(c) for c in cards]
    if clauses[-1] != 1 or max(clauses) > 2 or sum(1 for x in clauses if x > 1) > 2:
        return False
    cats = []
    for c in cards:
        for s in c:
            if '比' in s: cats.append('numeric')
            elif '不在' in s: cats.append('neg')
            elif s.startswith('只有'): cats.append('only')
    if cats.count('neg') > 2 or cats.count('only') > 1:
        return False
    if cats.count('numeric') > (3 if n == 7 else 2):
        return False
    # 谎言可察
    bs = a['bs']
    for k in range(2, n + 1):
        for comb in itertools.combinations(range(n), k):
            z = m.all
            for i in comb:
                z &= bs[i]
                if z == 0:
                    return True
            if z == 0:
                return True
    return False


def best_order(d, m, speakers):
    """枚举卡序，最大化本人自述覆盖，且必须通过全部位集闸门。"""
    n = len(d['cards'])
    h = speakers.index(d['thief'])
    false_card = h
    v_slot = n - 1
    slots = [i for i in range(n) if i not in (h, v_slot)]
    singles = [i for i, c in enumerate(d['cards']) if len(c) == 1 and i != false_card]
    best = None
    tested = 0
    for vcard in singles:
        rest_cards = [i for i in range(n) if i not in (false_card, vcard)]
        for perm in itertools.permutations(rest_cards):
            order = [None] * n
            order[h] = false_card
            order[v_slot] = vcard
            for slot, ci in zip(slots, perm):
                order[slot] = ci
            cover = sum(1 for slot, ci in enumerate(order)
                        for s in d['cards'][ci] if speakers[slot] in letters_in(s))
            total = sum(len(d['cards'][ci]) for ci in order)
            drift = sum(abs(ci - slot) for slot, ci in enumerate(order))
            key = (cover, -drift)
            if best is not None and key <= best[0]:
                continue
            cards = [d['cards'][i] for i in order]
            tested += 1
            if passes(m, cards, d, speakers):
                best = (key, order, cover, total, drift)
    return best, tested


def make_display(clause, speaker, lv):
    """自指字母→我；其余字母→中文名（写档用）。另出纯「我」版供设计验证。"""
    pure = re.sub(r'[A-FV]', lambda m: '我' if m.group() == speaker else m.group(), clause)
    arch = re.sub(r'[A-FV]',
                  lambda m: '我' if m.group() == speaker else NAMES[lv][m.group()], clause)
    return arch, pure


def main():
    data = json.loads(SRC.read_text(encoding='utf8'))
    out = []
    for d in data:
        if d['level'] not in (4, 5, 6, 7):
            out.append(d)
            continue
        lv, n = d['level'], len(d['cards'])
        speakers = list(d['card_speakers'])
        m = M7(d) if n == 7 else M6(d)
        best, tested = best_order(d, m, speakers)
        if best is None:
            raise SystemExit(f'第{lv}关：没有通过全部闸门的卡序')
        _, order, cover, total, drift = best
        cards = copy.deepcopy([d['cards'][i] for i in order])
        roles = copy.deepcopy([d['clause_roles'][i] for i in order])
        baseline = sum(1 for cr in d['clause_roles'] for p in cr if p.get('self_ref'))
        display, archive = [], []
        for slot, ci in enumerate(order):
            sp = speakers[slot]
            a, p = [], []
            for clause in d['cards'][ci]:
                x, y = make_display(clause, sp, lv)
                a.append(x); p.append(y)
            archive.append(a); display.append(p)
            for part in roles[slot]:
                part['speaker'] = sp
                part['self_ref'] = sp in letters_in(part['text'])
        new = dict(d)
        new.update(
            version='v15', cards=cards, display_cards=display,
            clause_roles=[list(x) for x in roles], card_speakers=speakers,
            suspects=NAMES[lv], archive_texts=archive,
            order_table=[dict(slot=i + 1, speaker=speakers[i], name=NAMES[lv][speakers[i]],
                              from_slot=order[i] + 1, predicate=cards[i],
                              design_text=display[i], archive_text=archive[i],
                              self_narrated=any(x['self_ref'] for x in roles[i]))
                         for i in range(n)],
            self_narration=dict(covered=cover, total=total, baseline=baseline,
                                candidates_tested=tested),
            theme_note=LEVEL_NOTE[lv],
            design_frozen=dict(room=d['room'], doors=d['doors'], objects=d['objects'],
                               target=d['target'], thief=d['thief'],
                               predicate_multiset=sorted(s for c in d['cards'] for s in c)),
        )
        out.append(new)
        print(f"第{lv}关 自述 {cover}/{total}（v14 {baseline}/{total}）"
              f" 卡序 {[i+1 for i in order]} 漂移{drift} 验证候选{tested}")
        for row in new['order_table']:
            print(f"  卡{row['slot']} {row['speaker']} {row['name']}："
                  f"{'、'.join(row['archive_text'])}  ←原卡{row['from_slot']}"
                  f"{' [本人自述]' if row['self_narrated'] else ''}")
    dst = ROOT / 'design_selected_v15.json'
    dst.write_text(json.dumps(out, ensure_ascii=False, indent=2), encoding='utf8')
    print('已写入', dst)


if __name__ == '__main__':
    main()
