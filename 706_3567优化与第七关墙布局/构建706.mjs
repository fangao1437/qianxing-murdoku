// 706：以705为基准，写入3567关 v16内容、浅蓝提示、自述口径与第七关单墙位微调。
// 仅修改19条 5/6/7 关卡卡面文本和内嵌客户端脚本；705原档保留。
import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const R = await import(pathToFileURL(ROOT + '/qianxing-murdoku-tool/project-tools/gil/gilread.mjs'));
const W = await import(pathToFileURL(ROOT + '/qianxing-murdoku-tool/project-tools/gil/gilwrite.mjs'));
const INPUT = path.join(DIR, '../705_可见卡框定位与教程文案修复/705_可见卡框定位与教程文案修复.gil');
const OUTPUT = path.join(DIR, '706_3567优化与第七关墙布局.gil');
const LUA = fs.readFileSync(path.join(ROOT, 'qianxing-murdoku/dist/client_script.lua'));
const expected = {
  5: [
    '我与C火漆验印在同一房间',
    'E证物登记在椅子上',
    'E证物登记在地毯上',
    'B夜勘记录不在桌子旁边、我在椅子上',
    'A封条保管在椅子上、C火漆验印在桌子旁边',
    'B夜勘记录与C火漆验印不在同一房间',
  ],
  6: [
    'B靛青描图不在地毯旁边',
    'E蓝图管理在雕塑旁边、F工地放样在椅子旁边',
    'D朱批校样在桌子旁边',
    'C野外测绘在书架旁边',
    'B靛青描图在书架旁边',
    'A晒图学徒不在植物旁边、C野外测绘在桌子旁边',
    '只有A晒图学徒在椅子上',
  ],
  7: [
    'C誊写员在地毯上',
    'V藏卷人在地毯上',
    'B转架管理在椅子上、E线装匠人在椅子上',
    'B转架管理在植物旁边、E线装匠人独自在房间',
    'V藏卷人不在桌子旁边',
    'A铜钥保管在植物旁边',
  ],
};
assert.equal(W.markerOf(LUA), 'v706', '内嵌脚本必须是v706');
const g = R.readGil(INPUT);
const before = new Map(g.recs.map(r => [r.id, R.encodeMsg([r.field])]));
const changed = [];
const changedStatic = [];
function setTextRecord(name, value) {
  const r = g.recs.find(x => x.name === name);
  assert(r, `缺少静态记录 ${name}`);
  const leaves = R.textsOf(r.field.sub, []);
  const target = leaves.find(f => f.payload.toString('utf8') !== name);
  assert(target, `记录 ${name} 没有文本叶子`);
  target.payload = Buffer.from(value, 'utf8');
  target.len = target.payload.length;
  target.sub = null;
  changed.push(r.id);
  changedStatic.push(r.id);
}
for (const lv of [5, 6, 7]) {
  for (let i = 0; i < expected[lv].length; i++) setTextRecord(`what.${lv}.${i + 1}`, expected[lv][i]);
}
const script = W.findScriptLeaf(g);
assert(script, '705基线缺少内嵌脚本记录');
const scriptId = script.field;
scriptId.payload = LUA;
scriptId.len = LUA.length;
scriptId.sub = null;
changed.push(scriptId);
const uniqueChanged = [...new Set(changed.map(x => typeof x === 'object' ? x.id : x))];
const rep = W.writeGil(g, OUTPUT, {
  label: '706 3567关v16线索、浅蓝提示、自述与第七关墙布局微调',
  expectRecs: 8300,
  expectMarker: 'v706',
  assert(g2) {
    assert.equal(g2.recs.length, before.size);
    const outScript = W.findScriptLeaf(g2);
    assert(outScript && outScript.buf.equals(LUA), '内嵌脚本未按预期写入');
    for (const r of g2.recs) {
      if (r.id === scriptId.id) continue;
      const same = R.encodeMsg([r.field]).equals(before.get(r.id));
      assert(same || changed.includes(r.id), `白名单外静态记录发生变化：${r.name}`);
    }
    for (const lv of [5, 6, 7]) {
      for (let i = 0; i < expected[lv].length; i++) {
        const r = g2.recs.find(x => x.name === `what.${lv}.${i + 1}`);
        const vals = R.textsOf(r.field.sub, []).map(f => f.payload.toString('utf8'));
        assert(vals.includes(expected[lv][i]), `what.${lv}.${i + 1} 写入值不对`);
      }
    }
    return true;
  },
});
const outGil = fs.readFileSync(OUTPUT);
const audit = {
  version: 706,
  input: path.basename(INPUT),
  output: path.basename(OUTPUT),
  sha256: crypto.createHash('sha256').update(outGil).digest('hex'),
  records: rep.recs,
  bytes: rep.bytes,
  fieldDiffs: rep.diffs,
  changedStaticRecords: changedStatic,
  changedStaticCount: changedStatic.length,
  embeddedLuaMarker: rep.marker,
  source: '567关线索重构_695基准_v16 + qianxing-murdoku/lua/levels/case_003.lua/case_005.lua/case_006.lua/case_007.lua',
  changes: [
    '第3关保留695已验收谜团结构，随705基线重新嵌入',
    '第5/6/7关采用v16新口径线索与家具布局',
    '浅蓝提示按运行时 Core:clue_hint 逐卡同步',
    '本人相关线索按v16卡序保留可自述项，不新增线索',
    '第7关墙位 v4,4 → v4,3，门/家具/线索/答案不变；缩略图随 levels.ui_list 同步',
  ],
};
fs.writeFileSync(path.join(DIR, '706_构建审计.json'), JSON.stringify(audit, null, 2), 'utf8');
console.log(JSON.stringify(audit, null, 2));
