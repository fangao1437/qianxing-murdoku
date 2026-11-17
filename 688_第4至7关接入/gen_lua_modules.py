"""把 688_关卡数据.json 序列化成内嵌 Lua 可接受的压缩模块文本 + 静态文本清单。

产出：
  688_内嵌Lua_补丁.json   { marker, replacement } 列表（可反向还原逐字节）
  688_Lua模块.lua         4 个完整 __M[...] 模块（供源码同步与 luac 校验）
  688_静态文本补丁.json   逐条文本记录的旧值→新值 / 新增清单
"""
import json, pathlib, sys
sys.stdout.reconfigure(encoding='utf-8')
ROOT = pathlib.Path(__file__).resolve().parent
DATA = json.loads((ROOT / '688_关卡数据.json').read_text(encoding='utf8'))


def L(v, indent=0):
    """Lua 值序列化（仅用 [--key--] / 数字 / 字符串 / 布尔 / 数组）。"""
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if v is None:
        return 'nil'
    if isinstance(v, (int, float)):
        return str(v)
    if isinstance(v, str):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
    if isinstance(v, list):
        return '{' + ', '.join(L(x, indent + 1) for x in v) + '}'
    if isinstance(v, dict):
        # 纯数组键（1..n 连续）用位置写法；其余用字符串键
        if v and all(isinstance(k, int) for k in v) and sorted(v) == list(range(1, len(v) + 1)):
            return '{' + ', '.join(L(v[i], indent + 1) for i in sorted(v)) + '}'
        parts = []
        for k, val in v.items():
            key = '[' + L(k) + ']'
            parts.append(key + ' = ' + L(val, indent + 1))
        return '{' + ', '.join(parts) + '}'
    raise TypeError(type(v))


def module(lv, lua):
    return (f'__M["levels.case_{lv:03d}"] = function()\n'
            f' return {L(lua)}\n'
            f'end\n')


def main():
    mods, patches, texts = [], [], {}
    for item in DATA['levels']:
        lv, lua = item['level'], item['lua']
        mods.append(module(lv, lua))
        texts[str(lv)] = item['texts']
    (ROOT / '688_Lua模块.lua').write_text('\n'.join(mods), encoding='utf8')

    # 补丁 1：LIST 追加 3 项（定点替换，反向可还原）
    old_list = ('local LIST = {\n'
                '  "levels.case_001",\n'
                '  "levels.case_002",\n'
                '  "levels.case_003",\n'
                '  "levels.case_004",\n'
                '}')
    new_list = ('local LIST = {\n'
                '  "levels.case_001",\n'
                '  "levels.case_002",\n'
                '  "levels.case_003",\n'
                '  "levels.case_004",\n'
                '  "levels.case_005",\n'
                '  "levels.case_006",\n'
                '  "levels.case_007",\n'
                '}')
    patches.append(dict(name='LIST 注册 5/6/7 关', old=old_list, new=new_list))

    # 补丁 2：case_004 模块整体替换（由构建脚本按 marker 边界定位）
    patches.append(dict(name='case_004 覆盖为 v15 设计',
                        marker='__M["levels.case_004"] = function()',
                        replacement=mods[0].replace('case_004', 'case_004')))
    # 补丁 3：在 case_004 模块后插入 005/006/007
    patches.append(dict(name='新增 case_005/006/007 模块',
                        marker='__M["levels.case_004"] = function()',
                        insert_after=''.join(mods[1:])))
    (ROOT / '688_内嵌Lua_补丁.json').write_text(
        json.dumps(dict(version='688', patches=patches, modules=mods),
                   ensure_ascii=False, indent=2), encoding='utf8')
    (ROOT / '688_静态文本补丁.json').write_text(
        json.dumps(dict(rule='who/what/letter 静态文本；新增 5/6/7 关行控件，'
                             '第4关覆盖人名与本人自述卡面',
                        texts=texts), ensure_ascii=False, indent=2), encoding='utf8')
    print('模块字节数', [len(m.encode('utf8')) for m in mods])
    for m in mods:
        print(' ', m.split('\n')[0], '->', m.split('\n')[1][:100])
    print('已生成 688_Lua模块.lua / 688_内嵌Lua_补丁.json / 688_静态文本补丁.json')


if __name__ == '__main__':
    main()
