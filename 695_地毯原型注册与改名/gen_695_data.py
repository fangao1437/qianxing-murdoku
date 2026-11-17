"""695 · 数据/补丁规格生成（基于 694 最小增量）

用户 2026-11-15 21:41 反馈：
  1. 694 真机上三格地毯仍然不渲染。
  2. 把「墨绿誊写」改成「誊写员」。

★ 本轮真正的根因（结构性，实测确认，不是推测）：
  692 新建 furn.rug.4 / furn.rug.5 两套独立素材时，只补齐了
    「源 / 母本 / 引用三件套」+ things.childList + Lua 引用链，
  却漏了 .gil 里**两处原型注册表**：
    · /9/501 顶层「根/原型 ID 列表」：43 项，既有家具模板源 ID 全在
      （furn.rug 1073747149 / furn.rug.2 1073748252 / furn.rug.3 1073749968 /
       furn.plant.2 1073753953 …），新源 1073760711 / 1073760734 **不在**；
    · /9/502（#501=1073741844，ClientUIPrototypeHierarchyRoot）的 #503
      「母本列表」：33 项，既有母本 1073747157 / 1073748248 / 1073749965 全在，
      新母本 1073760712 / 1073760735 **不在**。
  ⇒ 引擎加载存档时不创建这两个新原型 ⇒ things 里的引用控件指向不存在的
    prefab ⇒ game.InstantiateClientUIControl(1073760711/…, board.rugs) 失败
    ⇒ 694 虽然把 `_spawn_whole_rug` 调用恢复了，但拿不到可用 prefab，
    三格地毯依旧空白。691/692/693 的「逐格手搭层」在真机又被
    `if self._furn_tpl_ok then return true end` 与 `_furn_arch_new` 两道门跳过，
    所以两条路径都落空。

695 修法（零新增记录、零谜题改动）：
  R1 把 2 个新源 ID 追加进 /9/501（43→45）。
  R2 把 2 个新母本 ID 追加进原型根 #503（33→35）。
  L1 内嵌 Lua 加一条「地毯模板实例化失败」诊断日志（不改成功路径）。
  T1 人名「墨绿誊写」→「誊写员」：Lua case_007 suspects[C].name 1 处
     + gil 静态文本 2 处（who 标题、what 正文），字母前缀 C 保留。
"""
import json, pathlib, copy, hashlib, sys
sys.stdout.reconfigure(encoding='utf-8')
ROOT = pathlib.Path(__file__).resolve().parent
P694 = ROOT.parent / '694_地毯渲染修复'

LUA694 = (P694 / '694_内嵌Lua_694.lua').read_text(encoding='utf8')
SPEC694 = json.loads((P694 / '694_设计与补丁.json').read_text(encoding='utf8'))
K694 = json.loads((P694 / '694_关卡数据.json').read_text(encoding='utf8'))
FURN694 = json.loads((P694 / '694_家具规格.json').read_text(encoding='utf8'))

# ── R1 / R2 原型注册表补丁规格 ────────────────────────────────────────
REG = dict(
    rootList=dict(
        path='/9/501', before=43, after=45,
        append=[1073760711, 1073760734],
        note='顶层根/原型 ID 列表；既有能显示的家具模板源 ID 全部在此'),
    protoRootChildList=dict(
        path='/9/502(#501=1073741844)/503', before=33, after=35,
        append=[1073760712, 1073760735],
        note='ClientUIPrototypeHierarchyRoot 的母本列表；既有家具母本全部在此'),
    thingsChildList=dict(
        path='things/#503', count=13, append=[],
        note='692 已追加两个引用控件 1073760713 / 1073760736，本轮不动'),
    fieldOrderFix=dict(
        idRange=[1073760711, 1073760756], count=46,
        rule='把每条记录的顶层 #504（父控件 ID）移到第一个 #505 状态块之前，'
             '与所有既有可显示模板同构（既有 rug/plant.2 的 #504 都在记录开头）',
        evidence='692 构建器用 f.sub.push(#504) ⇒ 46 条新记录的父字段全落在记录末尾；'
                 '既有 1073748254 / 1073748253 / 1073748248 / 1073749162 / 1073753948 都在开头',
        note='附加保险：protobuf 字段顺序理论上无关，但存档编辑器历史上出现过顺序依赖；'
             '本项零谜题改动、完全可逆'),
    prefabChain=[
        'furn.rug.4 源 #1073760711 → /9/501 注册',
        'furn.rug.4 母本 #1073760712 → 原型根 #503 注册',
        'furn.rug.4 引用 #1073760713 → things.childList',
        'furn.rug.5 源 #1073760734 → /9/501 注册',
        'furn.rug.5 母本 #1073760735 → 原型根 #503 注册',
        'furn.rug.5 引用 #1073760736 → things.childList',
        'cfg.furn_tpl_prefab.rug_4/rug_5 = 新源 ID（694 已有）',
        'F.layout → TPL_KEY.carpet.L3a/L3b → _spawn_furn_tpl → _spawn_whole_rug',
    ],
)

# ── L1 / T1 Lua 补丁（可逆、逐字节可还原 694） ───────────────────────
P_NAME_OLD, P_NAME_NEW = '墨绿誊写', '誊写员'
assert LUA694.count(P_NAME_OLD) == 1, '694 Lua 里「墨绿誊写」应恰好 1 处'

P_LOG_OLD = '''    local ok;ok,obj=pcall(game.InstantiateClientUIControl,prefab,parent)
    if not ok or not obj then return false end
    obj.name="rug."..cell_id'''
P_LOG_NEW = '''    local ok;ok,obj=pcall(game.InstantiateClientUIControl,prefab,parent)
    if not ok or not obj then
      -- 695：原型注册失败时留一条可检索日志，便于真机定位 prefab / parent。
      if print then print("[murdoku] 地毯模板实例化失败：ckey="..tostring(ckey)
        .." prefab="..tostring(prefab).." ok="..tostring(ok)
        .." parent="..tostring(parent ~= nil and parent.name or "nil")) end
      return false
    end
    obj.name="rug."..cell_id'''
assert LUA694.count(P_LOG_OLD) == 1, '诊断日志锚点不唯一'

LUA_PATCHES = [
    dict(name='T1 第7关 C 姓名 墨绿誊写 → 誊写员',
         old=P_NAME_OLD, new=P_NAME_NEW, count=1),
    dict(name='L1 _spawn_whole_rug 实例化失败诊断日志',
         old=P_LOG_OLD, new=P_LOG_NEW, count=1),
]
s = LUA694
for p in LUA_PATCHES:
    assert s.count(p['old']) == p['count'], '锚点数不符：' + p['name']
    s = s.replace(p['old'], p['new'], p['count'])
back = s
for p in reversed(LUA_PATCHES):
    back = back.replace(p['new'], p['old'], p['count'])
assert back == LUA694, 'Lua 补丁无法反向逐字节还原 694'
LUA695 = s
(ROOT / '695_内嵌Lua_695.lua').write_text(LUA695, encoding='utf8')

# ── T2 静态文本补丁（精确整串匹配，不做子串替换） ────────────────────
TEXT_PATCHES = [
    dict(name='第7关卡1正文', old='C墨绿誊写比我靠左2列', new='C誊写员比我靠左2列', count=1),
    dict(name='第7关 C 说话人标题', old='墨绿誊写', new='誊写员', count=1),
]

# ── 数据文件同步 ──────────────────────────────────────────────────────
K695 = copy.deepcopy(K694)
assert K695['names']['7']['C'] == '墨绿誊写'
K695['names']['7']['C'] = '誊写员'
(ROOT / '695_关卡数据.json').write_text(json.dumps(K695, ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '695_家具规格.json').write_text(json.dumps(FURN694, ensure_ascii=False, indent=2), encoding='utf8')
(ROOT / '695_静态文本补丁.json').write_text(
    json.dumps(dict(texts=TEXT_PATCHES, note='精确整串匹配；who 纯人名不加字母，what 保留字母前缀 C'),
               ensure_ascii=False, indent=2), encoding='utf8')

SPEC695 = copy.deepcopy(SPEC694)
SPEC695['version'] = 695
SPEC695['base'] = dict(file='../694_地毯渲染修复/694_地毯渲染修复.gil',
                       luaBytes=len(LUA694.encode('utf8')),
                       sha256Lua=hashlib.sha256(LUA694.encode('utf8')).hexdigest())
SPEC695['rootCause'] = dict(
    summary='692 新建的三格地毯素材只补了三件套与 things.childList，漏了 /9/501 原型根 ID 列表'
            ' 与 ClientUIPrototypeHierarchyRoot 的 #503 母本列表 ⇒ 真机上两个新 prefab 根本不存在',
    evidence=[
        '/9/501 共 43 项：furn.rug 1073747149 / furn.rug.2 1073748252 / furn.rug.3 1073749968'
        ' / furn.plant.2 1073753953 全在；1073760711、1073760734 不在',
        '原型根 #503 共 33 项：母本 1073747157 / 1073748248 / 1073749965 / 1073753951 全在；'
        '1073760712、1073760735 不在',
        'things.childList 13 项已含引用 1073760713 / 1073760736（692 已补）',
        '694 的 _spawn_furn_tpl 五个 rug 变体 mock 全 true:true，但真机 prefab 实例化拿不到原型',
        'furn 手搭层被 `if self._furn_tpl_ok then return true end` 与 `_furn_arch_new` 两道门跳过',
    ],
    fix='R1/R2 补齐两处原型注册表；R3 把 44 条新素材记录的顶层 #504 与既有模板对齐；'
        '保留 694 的整块模板路径与逐格关闭；L1 加实例化失败日志',
)
SPEC695['registryFix'] = REG
SPEC695['luaPatches'] = LUA_PATCHES
SPEC695['staticTextPatches'] = TEXT_PATCHES
SPEC695['names'] = K695['names']
SPEC695['carpetRender'] = copy.deepcopy(SPEC694.get('carpetRender', {}))
SPEC695['carpetRender']['registry'] = 'R1 /9/501 45 项 + R2 原型根 #503 35 项（695 补齐）'
(ROOT / '695_设计与补丁.json').write_text(json.dumps(SPEC695, ensure_ascii=False, indent=2), encoding='utf8')

order_md = (P694 / '694_顺序对照表.md').read_text(encoding='utf8')
order_md = order_md.replace('694', '695') + '\n\n> 695：第7关 C 姓名「墨绿誊写」→「誊写员」；卡序、谓词、答案、真假向量不变。\n'
(ROOT / '695_顺序对照表.md').write_text(order_md, encoding='utf8')

# Windows 的 write_text 会把 \n 写成 \r\n；内嵌 Lua 必须与 694 一样保持 LF，
# 否则 script leaf 每行都变、且反向还原字节闸门会失真。统一压回 LF。
for p in ROOT.glob('695_*'):
    if p.suffix in ('.lua', '.json', '.md'):
        b = p.read_bytes()
        if b'\r\n' in b:
            p.write_bytes(b.replace(b'\r\n', b'\n'))

print('695 数据/补丁规格生成完成')
print('  694 Lua 字节', len(LUA694.encode('utf8')), '→ 695', len(LUA695.encode('utf8')))
print('  注册表：/9/501 43→45；原型根 #503 33→35')
print('  Lua 补丁', len(LUA_PATCHES), '项；静态文本补丁', len(TEXT_PATCHES), '项')
print('  反向还原 694：逐字节一致 ✓')
