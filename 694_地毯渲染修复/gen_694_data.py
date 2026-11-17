"""694 · 真机反馈修正（基于 693 最小增量）

用户 2026-11-15 20:46 反馈：
  1 地毯仍然没渲染。
  2 删掉第3关右上角的装饰用植物。

根因（实测确认）：
  685~690 的 `_spawn_furn_tpl` 对 rug 分支走 `_spawn_whole_rug` 整块模板实例化，
  真机 16:51 截图（第6关）能看到米黄色带边框的地毯方块。
  691 起把该分支改成「隐藏所有 rug 实例 + return false」，整块模板不再画；
  而逐格 `rug_cell_els` 走 `furn` 属性，在 `_furn_tpl_ok=true`（真机 things
  prefab 可用，桌椅/书架/植物/雕塑都靠它显示）时被 `if self._furn_tpl_ok
  then return true end` 直接跳过 ⇒ 两条绘制路径全断，691/692/693 真机全空白。
  693 误判为「逐格路径被关掉」，只改了按边开放算法，没有恢复模板，故仍空白。

694 修法：
  P1 恢复整块地毯模板实例化（`_spawn_whole_rug`），并纳入新建的 rug_4/rug_5
     独立 216×216 L 形素材；与桌椅等完全同一条引用路线。
  P2 关闭逐格 `rug_cell_els`：既杜绝双绘，也彻底消除「三张单格拼接」观感，
     边框只由整块模板沿外围绘制。
  M1 第3关 `objects.植物` 去掉 (1,6) 装饰株，只保留 (1,1) 功能株；
     书架 (1,5) + 雕塑 (2,6) 不变。
"""
import json, pathlib, copy, hashlib, sys
sys.stdout.reconfigure(encoding='utf-8')
ROOT = pathlib.Path(__file__).resolve().parent
P693 = ROOT.parent / '693_真机修正'
LUA693 = (P693 / '693_内嵌Lua_693.lua').read_text(encoding='utf8')
SPEC693 = json.loads((P693 / '693_设计与补丁.json').read_text(encoding='utf8'))
K693 = json.loads((P693 / '693_关卡数据.json').read_text(encoding='utf8'))
FURN693 = json.loads((P693 / '693_家具规格.json').read_text(encoding='utf8'))
TEXTS693 = json.loads((P693 / '693_静态文本补丁.json').read_text(encoding='utf8'))

MR693 = {m['name']: m for m in SPEC693['moduleReplacements']}
MOD3_693 = next(m for m in SPEC693['moduleReplacements'] if 'case_003' in m['name'])

# ── M1 第3关：删除 (1,6) 装饰植物 ─────────────────────────────────────
OLD_PLANT = '{["r"] = 1, ["c"] = 1}, {["r"] = 1, ["c"] = 6}'
NEW_PLANT = '{["r"] = 1, ["c"] = 1}'
assert MOD3_693['newModule'].count(OLD_PLANT) == 1, 'case_003 植物锚点不唯一'
MOD3_694 = MOD3_693['newModule'].replace(OLD_PLANT, NEW_PLANT)

K694 = copy.deepcopy(K693)
L3 = K694['level3']['lua']
assert L3['objects']['植物']['cells'] == [{'r': 1, 'c': 1}, {'r': 1, 'c': 6}]
L3['objects']['植物']['cells'] = [{'r': 1, 'c': 1}]
# hint_preview：(1,6) 的四邻 (1,5) 书架 / (2,6) 雕塑 均不可站、另两邻越界
# ⇒ 删除后 beside_object「植物」的浅蓝提示格不变，仍为 1:2 / 2:1。
assert L3['hint_preview']['2']['cells'] == ['1:2', '2:1']
assert L3['hint_preview']['6']['cells'] == ['1:2', '2:1']

# ── P1 地毯整块模板实例化 ─────────────────────────────────────────────
i1 = LUA693.find('  if ckey=="rug" or ckey=="rug_2" or ckey=="rug_3"\n'
                 '     or ckey=="rug_4" or ckey=="rug_5" then\n')
assert i1 > 0, 'P1 起点未找到'
j1 = LUA693.find('\n  end\n', i1)
assert j1 > i1, 'P1 终点未找到'
P1_OLD = LUA693[i1:j1 + len('\n  end\n')]
assert 'return false' in P1_OLD and 'string.find(k,"|rug"' in P1_OLD, 'P1 内容不符'
P1_NEW = '''  if ckey=="rug" or ckey=="rug_2" or ckey=="rug_3"
     or ckey=="rug_4" or ckey=="rug_5" then
    -- 694：恢复整块地毯模板实例化（688/689/690 真机可显示路径）。
    -- 三格 L 形用独立新建的 furn.rug.4/.5（216×216，边框只沿外围），
    -- 与桌椅/书架/植物/雕塑完全相同的一条素材引用路线，不复用、不拉伸。
    return self:_spawn_whole_rug(cell_id,ctrl,ckey,prefab,cw,ch,
      (self._furn_span and self._furn_span[cell_id]) or {r=1,c=1},
      (self._furn_off and self._furn_off[cell_id]) or {dx=0,dy=0})
  end
'''

# ── P2 关闭逐格手搭层（消除双绘 + 单格拼接观感） ──────────────────────
i2 = LUA693.find('      local cellset = {}\n')
assert i2 > 0, 'P2 起点未找到'
j2 = LUA693.find('      res.pieces = res.pieces or {}', i2)
assert j2 > i2, 'P2 终点未找到'
P2_OLD = LUA693[i2:j2]
assert P2_OLD.count('F.rug_cell_els') == 1, 'P2 内容不符'
P2_NEW = '''      -- 694：地毯只走整块模板（_spawn_whole_rug）。逐格手搭层全部关闭，
      -- 既避免与模板双绘，也不再出现「三张单格地毯拼接」的观感。
'''

PATCHES = [
    dict(name='P1 恢复地毯整块模板实例化（含 L3a/L3b 新素材）',
         old=P1_OLD, new=P1_NEW, count=1),
    dict(name='P2 关闭逐格 rug_cell_els（防双绘 / 防拼接）',
         old=P2_OLD, new=P2_NEW, count=1),
]
# 可逆性自检：逐个应用后能反向逐字节还原 693
s = LUA693
for p in PATCHES:
    assert s.count(p['old']) == p['count'], '锚点数不符: ' + p['name']
    s = s.replace(p['old'], p['new'], p['count'])
# 模块替换（同一 marker、同一边界）
i = s.find(MOD3_693['marker'])
j = s.find('\nend', i)
assert i > 0 and j > i
s = s[:i] + MOD3_694.strip() + s[j + 4:]
back = s.replace(MOD3_694.strip(), LUA693[LUA693.find(MOD3_693['marker']):
                                        LUA693.find('\nend', LUA693.find(MOD3_693['marker'])) + 4])
for p in reversed(PATCHES):
    back = back.replace(p['new'], p['old'], p['count'])
assert back == LUA693, '补丁无法反向逐字节还原 693'

LUA694 = s
(ROOT / '694_内嵌Lua_694.lua').write_text(LUA694, encoding='utf8')

# ── 输出规格 ──────────────────────────────────────────────────────────
SPEC694 = dict(
    version=694,
    base=dict(file='../693_真机修正/693_第三关与三格地毯.gil',
              luaBytes=len(LUA693.encode('utf8')),
              sha256Lua=hashlib.sha256(LUA693.encode('utf8')).hexdigest()),
    rootCause=dict(
        summary='691 起 rug 分支改为隐藏实例 + return false；逐格 rug_cell_els 走 furn 属性，'
                '又被 _furn_tpl_ok 跳过 ⇒ 两条绘制路径全断',
        evidence=['688/689/690: return self:_spawn_whole_rug(...) → 真机 16:51 截图有地毯方块',
                  '691/692/693: for ... SetVisible(false) ... return false',
                  'furn handler: if self._furn_tpl_ok then return true end（1~7 关家具模板可用 ⇒ 恒真）'],
        fix='恢复 _spawn_whole_rug 整块模板路径，纳入 rug_4/rug_5；关闭逐格手搭层'),
    luaPatches=PATCHES,
    moduleReplacements=[dict(name='case_003 删右上角装饰植物', marker=MOD3_693['marker'],
                             newModule=MOD3_694)],
    names=SPEC693['names'],
    nameRules=SPEC693['nameRules'],
    level3=dict(order=K694['level3']['order'],
                gates=SPEC693['level3']['gates'],
                legalOrders=SPEC693['level3']['legalOrders'],
                selfNarration=SPEC693['level3']['selfNarration'],
                furniture=dict(书架=[4], 植物=[0], 雕塑=[11]),
                note='V 房间：1 书架 (1,5) + 1 雕塑 (2,6)；装饰植物 (1,6) 已删；'
                     '功能植物 (1,1) 保留（线索「在植物旁边」依赖它）'),
    level4=SPEC693['level4'],
    carpet=SPEC693['carpet'],
    carpetRender=dict(
        path='F.layout → TPL_KEY.carpet → build_layout.furn_tpl/span/offset → '
             '_spawn_furn_tpl → _spawn_whole_rug → board.rugs → InstantiateClientUIControl',
        templates=dict(single='furn.rug (108×108)', h2='furn.rug.2 (216×108)',
                       v2='furn.rug.3 (108×216)',
                       L3a='furn.rug.4 (216×216, 缺右下)', L3b='furn.rug.5 (216×216, 缺左下)'),
        perCellEls='disabled（694 P2）',
        doubleDraw='none（逐格关闭；模板唯一路径）'),
)
(ROOT / '694_设计与补丁.json').write_text(json.dumps(SPEC694, ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '694_关卡数据.json').write_text(json.dumps(K694, ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '694_家具规格.json').write_text(json.dumps(FURN693, ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '694_静态文本补丁.json').write_text(json.dumps(dict(texts={}, note='694 静态文本零改动'),
                                                       ensure_ascii=False, indent=2), encoding='utf8')
# 顺序对照表：内容不变，仅换标题
order_md = (P693 / '693_顺序对照表.md').read_text(encoding='utf8')
order_md = order_md.replace('693', '694').replace('1 植物', '0 植物（装饰株已删）')
(ROOT / '694_顺序对照表.md').write_text(order_md, encoding='utf8')

print('694 数据与补丁生成完成')
print('  Lua 补丁', len(PATCHES), '项；模块替换 1 项（case_003）')
print('  693 Lua 字节', len(LUA693.encode('utf8')), '→ 694', len(LUA694.encode('utf8')))
print('  第3关植物', L3['objects']['植物']['cells'], '书架', L3['objects']['书架']['cells'],
      '雕塑', L3['objects']['雕塑']['cells'])
print('  地毯路径：整块模板 _spawn_whole_rug；逐格 els 已关闭')
print('  反向还原 693：逐字节一致 ✓')
