// 653：基于 652 的静态美术叶层分类与父级显隐门控
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import {
  readGil, encodeMsg, cloneField, asIdList, setChildList, ensureChildListTop,
  textsOf, stateBlocks, pairOf, pairValue,
} from '../tools/gil/gilread.mjs';
import { writeGil, findScriptLeaf } from '../tools/gil/gilwrite.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const INPUT = path.join(HERE, '652_分类整理优化.gil');
const OUTPUT = path.join(HERE, '653_全树分类优化.gil');
const LUA = path.join(HERE, '653_全树分类优化.lua');
const AUDIT = path.join(HERE, '653_全树分类审计.json');
const hash = b => crypto.createHash('sha256').update(b).digest('hex');
const expectedInputSha = '57aefad84dc151d0f80fd3102ac7d1b5fbb2fb5fb1988c1d5afe8e8a48a727e2';

const original = readGil(INPUT);
assert.equal(hash(original.src), expectedInputSha, '输入不是已审计的 652_分类整理优化');
const g = readGil(INPUT);
const old = new Map(original.recs.map(r => [Number(r.id), r]));
const byId = new Map(g.recs.map(r => [Number(r.id), r]));
const R = name => { const r = g.recs.find(x => x.name === name); assert(r, 'missing ' + name); return r; };
const kids = r => r?.childList ? (asIdList(r.childList.payload, true) || []).map(Number) : [];
const setKids = (r, ids) => {
  const cl = ensureChildListTop(r);
  setChildList(cl, ids);
  r.childList = r.field.sub.find(f => f === cl);
};
const scriptOriginal = findScriptLeaf(original).buf.toString('utf8');
const scriptRefs = new Set(g.recs.map(r => r.name).filter(n => n && (scriptOriginal.includes('"' + n + '"') || scriptOriginal.includes("'" + n + "'"))));
const getChildNames = new Set([...scriptOriginal.matchAll(/GetChild\s*\(\s*["']([^"']+)["']\s*\)/g)].map(m => m[1]));
const forbiddenParent = /^(grp652\.|td\.|row\.|floor\.|cell\.|modal|block640\.|assets$|stage$|clues$|board\.floors$|tpl\.|home$|hint635\.)/;
const allowedParent = /^(art641\.(home|select|game)|art642\.select\.|labels$)/;
const forbiddenChild = /(^|\.)(hit|btn|stephit|face|letter|who|what|note|gray|x|assets|stage|board)$/;
const isLeaf = r => kids(r).length === 0;
const isSafeLeaf = r => isLeaf(r) && r.name && !scriptRefs.has(r.name) && !getChildNames.has(r.name)
  && !forbiddenChild.test(r.name) && !/^row\.|^cell\.|^floor\./.test(r.name);

const groups = [];
const moved = new Set();
const changedParents = new Set();
let maxId = Number(g.maxId);
function remap(fields, from, to, depth = 0) {
  for (const f of fields || []) {
    if (!(depth === 0 && f.field === 504) && f.wt === 0 && Number(f.num) === from) f.num = BigInt(to);
    if (f.sub) remap(f.sub, from, to, depth + 1);
  }
}
function addGroup(parent, serial, ids) {
  const proto = R('art641.game');
  const field = cloneField(proto.field);
  const id = ++maxId;
  remap(field.sub, proto.id, id);
  const name = `grp653.static.${serial}.${parent.name}`;
  const nf = textsOf(field.sub, []).find(f => f.payload.toString('utf8') === proto.name);
  assert(nf, 'group name leaf missing');
  nf.payload = Buffer.from(name); nf.len = nf.payload.length;
  const pf = field.sub.find(f => f.field === 504 && f.wt === 0); assert(pf);
  pf.num = BigInt(parent.id);
  // 分类父级必须初始可见；子控件自己的显隐字段完全不改。
  for (const b of field.sub.filter(f => f.field === 505)) {
    const p503 = b.sub?.find(f => f.field === 503);
    const p14 = p503?.sub?.find(f => f.field === 14);
    const p17 = p14?.sub?.find(f => f.field === 17);
    if (p17) { p17.sub = []; p17.payload = Buffer.alloc(0); p17.len = 0; p17.isText = false; }
  }
  const rec = { id, name, parentId: Number(parent.id), field };
  setKids(rec, ids);
  for (const st of stateBlocks(field.sub, [])) {
    assert.equal(pairValue(pairOf(st, 504), 0), 0);
    assert.equal(pairValue(pairOf(st, 504), 1), 0);
    assert.equal(pairValue(pairOf(st, 505), 0), 1600);
    assert.equal(pairValue(pairOf(st, 505), 1), 900);
  }
  const siblings = kids(parent);
  const at = siblings.indexOf(ids[0]);
  assert(at >= 0, 'group first child is not a sibling');
  assert.deepEqual(siblings.slice(at, at + ids.length), ids, 'group must be a contiguous original run');
  setKids(parent, [...siblings.slice(0, at), id, ...siblings.slice(at + ids.length)]);
  changedParents.add(Number(parent.id));
  for (const cid of ids) {
    const child = byId.get(cid); assert(child);
    const parentField = child.field.sub.find(f => f.field === 504 && f.wt === 0); assert(parentField);
    assert.equal(Number(parentField.num), Number(parent.id));
    parentField.num = BigInt(id);
    child.parentId = id;
    moved.add(cid);
  }
  g.recHolder.push(field); g.recs.push(rec); byId.set(id, rec);
  groups.push({ id, name, parent: parent.name, parentId: Number(parent.id), count: ids.length, childIds: ids });
}

function collectGroups(parent) {
  const ids = kids(parent);
  const children = ids.map(id => byId.get(id)).filter(Boolean);
  let run = [];
  let serial = 0;
  const flush = () => {
    if (run.length >= 3) addGroup(parent, ++serial, run.map(r => Number(r.id)));
    run = [];
  };
  for (const child of children) {
    if (isSafeLeaf(child)) run.push(child); else flush();
  }
  flush();
}
function walkAllowed(parent) {
  if (parent.name !== 'root' && (forbiddenParent.test(parent.name || '') || !allowedParent.test(parent.name || ''))) return;
  const children = kids(parent).map(id => byId.get(id)).filter(Boolean);
  for (const child of children) if (!isLeaf(child)) walkAllowed(child);
  if (parent.name !== 'root' && allowedParent.test(parent.name || '')) collectGroups(parent);
}
walkAllowed(R('root'));
assert.equal(groups.length, 10, '分类段数量变化，拒绝生成');
assert.equal(moved.size, 518, '分类控件数量变化，拒绝生成');

// 更新 652 已存在的精确路径表：只替换路径数据和查找函数名，保留 find/sub/动态创建回退。
const root = R('root');
const runtime = []; const paths = new Map();
function walk(r, p) {
  const pp = [...p, r.name]; runtime.push(r); paths.set(Number(r.id), pp);
  for (const id of kids(r)) walk(byId.get(id), pp);
}
walk(root, []);
const countNames = new Map(); for (const r of runtime) countNames.set(r.name, (countNames.get(r.name) || 0) + 1);
const routes = runtime.filter(r => r.name && countNames.get(r.name) === 1 && (
  r.parentId === Number(root.id) || scriptOriginal.includes('"' + r.name + '"') || scriptOriginal.includes("'" + r.name + "'")
  || /^td\.(home|l1|l2)\.page\.\d+$/.test(r.name) || /^row\./.test(r.name)
));
const quote = s => JSON.stringify(s);
const routeLua = 'local STATIC_PATH_653 = {\n' + routes.map(r =>
  '  [' + quote(r.name) + '] = {' + paths.get(Number(r.id)).map(quote).join(',') + '},'
).join('\n') + '\n}\n' + `local function path_lookup_653(roots, name)
  local route = STATIC_PATH_653[name]
  if route == nil then return nil end
  for i = 1, #roots do
    local cur = roots[i]
    local ok, rn = pcall(function() return cur.name end)
    if ok and rn == route[1] then
      for k = 2, #route do
        local parent = cur
        local good, child = pcall(function() return parent:GetChild(route[k]) end)
        if not good or child == nil then cur = nil; break end
        cur = child
      end
      if cur ~= nil then
        local good, actual = pcall(function() return cur.name end)
        if good and actual == name then return cur end
      end
    end
  end
  return nil
end
`;
let script = scriptOriginal;
const start = script.indexOf('local STATIC_PATH_652 = {');
const end = script.indexOf('function Adapter:_build_name_index', start);
assert(start >= 0 && end > start, '找不到 652 路径表真实边界');
script = script.slice(0, start) + routeLua + '\n' + script.slice(end);
script = script.replaceAll('path_lookup_652', 'path_lookup_653');
fs.writeFileSync(LUA, script);
const leaf = findScriptLeaf(g);
leaf.field.payload = Buffer.from(script); leaf.field.len = leaf.field.payload.length; leaf.field.sub = null;

const expected = new Map(g.recs.map(r => [Number(r.id), encodeMsg([r.field])]));
function visualFields(r) { return encodeMsg((r.field.sub || []).filter(f => !(f.field === 504 && f.wt === 0) && f !== r.childList)); }
function flattened(gx) {
  const map = new Map(gx.recs.map(r => [Number(r.id), r])); const out = [];
  const groupIds = new Set(groups.map(x => x.id));
  function visit(r) { if (!groupIds.has(Number(r.id))) out.push(Number(r.id)); for (const id of kids(r)) visit(map.get(id)); }
  visit(map.get(Number(root.id))); return out;
}
const report = writeGil(g, OUTPUT, {
  label: '653 全树静态美术分类与父级门控', expectRecs: original.recs.length + groups.length, expectMarker: 'v635', quiet: true,
  assert: g2 => {
    assert.equal(g2.recs.length, expected.size);
    for (const r of g2.recs) {
      assert(expected.get(Number(r.id))?.equals(encodeMsg([r.field])), '磁盘记录不符 ' + r.name);
      const prev = old.get(Number(r.id));
      if (prev) assert(visualFields(prev).equals(visualFields(r)), '美术/交互字段变化 ' + r.name);
    }
    const map = new Map(g2.recs.map(r => [Number(r.id), r]));
    for (const r of g2.recs) for (const id of kids(r)) {
      assert(map.has(id), '断链 ' + id); assert.equal(map.get(id).parentId, Number(r.id), '双向父子不符 ' + r.name);
    }
    assert.deepEqual(flattened(g2), flattened(original), '绘制深度优先序改变');
    assert(findScriptLeaf(g2).buf.equals(Buffer.from(script)), '脚本不一致');
    assert(g2.trailer.equals(original.trailer));
    return true;
  },
});
const data = {
  base: path.basename(INPUT), inputSha256: hash(original.src), output: path.basename(OUTPUT), outputSha256: hash(report.g2.src),
  inputBytes: original.src.length, outputBytes: report.bytes,
  scriptBytesBefore: findScriptLeaf(original).len, scriptBytesAfter: Buffer.byteLength(script),
  recordsBefore: original.recs.length, recordsAfter: report.g2.recs.length,
  addedGroups: groups.map(({childIds, ...x}) => ({...x})), movedControls: moved.size, changedParents: changedParents.size,
  retainedRecordCount: original.recs.length - moved.size - changedParents.size,
  exactRoutes: routes.length,
  exclusions: {tutorialTrees: true, assetsRows: true, stage: true, boardCellsAndFurniture: true, modalAndHitAreas: true, templates: true, directGetChildNames: [...getChildNames]},
  checks: {diskReread: true, roundtrip: true, originalVisualAndInteractionFieldsUnchanged: true, flattenedOriginalDrawOrderUnchanged: true, noDanglingIds: true, bidirectionalTree: true, scriptEqualsDeliveredLua: true, trailerUnchanged: true},
  limitations: ['离线验证不能代替实机视觉与点击验收', '分类父级主要减少查找/显隐调用，不等同于同等幅度的渲染成本下降', '教程与动态控件未重挂，保留原直接子列表语义'],
};
fs.writeFileSync(AUDIT, JSON.stringify(data, null, 2));
console.log(JSON.stringify(data, null, 2));
