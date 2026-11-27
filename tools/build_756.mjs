// tools/build_756.mjs
// 基于 755_教程图文间距与视觉一致性精修/755_教程图文间距与视觉一致性精修.gil 构建 756_清理失效教程控件.gil
// 严格不覆盖旧档（750~755 均保留原样），原样保留 Top#11 单人房间人数配置与 755 全部视觉/交互修复。
//
// 本次 756 清理范围（经 749v8 -> 755 逐 ID 精确比对 + 全脚本引用核验）：
// 1. 删除教程精简后不再使用的 5 个整页子树（共 731 个控件）：
//    - td.l1.page.2 (137)、td.l1.page.4 (141)、td.l1.page.5 (159)、td.l1.page.6 (144)
//    - td.l2.page.1 (150)
// 2. 删除 8 个保留教程页内因布局合并/步骤精简/绿勾换贴图而失效隐藏的 141 个叶控件：
//    - td.home.page.1: 17 个（合并为 3 大卡后废弃的 rule.2.* 与 rule.4.*）
//    - td.l1.page.1:   22 个（多余的 step 5..8 整组 + 被 note 遮挡的 body.1.1/1.2）
//    - td.l1.page.3:   29 个（多余 step 5..8，保留复用做第 1 步对勾的 stepn.5.bg + 旧 stepn.1 细勾 + note.rule + 8 个 key610）
//    - td.l1.page.7:   20 个（多余 step 5..8，保留复用做第 1/2 步对勾的 stepn.5.bg/6.bg + 旧 stepn.1/2 细勾）
//    - td.l1.page.8:   24 个（多余 step 5..8，保留复用做第 1~3 步对勾的 stepn.5.bg/6.bg/7.bg + 旧 stepn.1/2/3 + body.1.1/1.2 + body.x5/x6）
//    - td.l2.page.2:    7 个（多余 step 4 整组 + 新首页隐藏的 prevbg/prevtext）
//    - td.l2.page.3:   17 个（多余 step 4，保留复用做第 1 步对勾的 stepn.4.bg + 旧 stepn.1 + 精简掉的 lgt.6..12 + body.1.0/2.0/2.2 + rewrite617.0/2）
//    - td.l2.page.4:    5 个（多余 step 4，保留复用做第 1/2 步对勾的 step.4/stepn.4.bg + 旧 stepn.1/2）
//    累计精准清理 731 + 141 = 872 个失效控件（总控件数 8731 -> 7859），严格走四道父子双向一致性与零残留闸门。
// 3. 同步更新内嵌脚本：
//    - 静态路径表 root/td.l1 与 root/td.l2 移除已删除的 5 个废页；
//    - tutorial_ui:M:_paint() 在存在 page_map 时仅遍历有效映射页，彻底消除对已删页面的无效查找开销；
//    - 更新构建标记为 v756。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { asIdList, setChildList, writeVarint, parseMsg, ID_LO, ID_HI, textsOf, KNOWN_TYPES } from './gil/gilread.mjs';
import { loadTree, findScriptLeaf, writeGil } from './gil/gilwrite.mjs';

const repo = fileURLToPath(new URL('../', import.meta.url));
const runTmp = fs.mkdtempSync(path.join(os.tmpdir(), 'murdoku-756-'));
const keepTmp = process.argv.includes('--keep-tmp');
const overwrite = process.argv.includes('--overwrite');

const base749 = path.join(repo, '749_背包商店右侧纸张切换动画/749_背包商店右侧纸张切换动画_v8.gil');
const base = path.join(repo, '755_教程图文间距与视觉一致性精修/755_教程图文间距与视觉一致性精修.gil');
const out = path.resolve(
  process.argv[2] && !process.argv[2].startsWith('--')
    ? process.argv[2]
    : path.join(repo, '756_清理失效教程控件/756_清理失效教程控件.gil')
);

if (!overwrite) assert(!fs.existsSync(out), '输出已存在，拒绝覆盖旧档（本项目习惯按版本号递增导出）：' + out);

const sha = (b) => createHash('sha256').update(b).digest('hex');
const g749 = loadTree(base749);
const g = loadTree(base);
assert.equal(
  sha(g.src),
  '7e186a6cba72cd7e68035d825804ef92bb138c794732f620373e35f94a68db87',
  '基准 755_教程图文间距与视觉一致性精修.gil SHA256 不匹配'
);

// ═════════════════════════════════════════════════════════════════════════════
// PART A：与 tools/gil/delete_controls.mjs 同构的顶层 #501/#503/#504 模型与四道闸门
// ═════════════════════════════════════════════════════════════════════════════
function isHidden(rec) {
  for (const f of rec.field.sub) {
    if (f.field !== 505 || !f.sub) continue;
    const s = f.sub.find((x) => x.field === 503 && x.sub);
    const c14 = s && s.sub.find((x) => x.field === 14 && x.sub);
    const c17 = c14 && c14.sub.find((x) => x.field === 17);
    if (c17 && c17.sub) {
      const f503 = c17.sub.find((y) => y.field === 503 && y.wt === 0);
      if (f503 && f503.num === 1n) return true;
    }
  }
  return false;
}

function buildModel(tree) {
  const nines = tree.filter((f) => f.field === 9 && f.sub);
  assert.equal(nines.length, 1, '期望恰好 1 个 #9 记录容器');
  const holder = nines[0].sub;
  const rls = holder.filter((f) => f.field === 501 && f.wt === 2 && !f.isText && asIdList(f.payload, true) !== null);
  assert(rls.length <= 1, '/9 顶层出现多个根对象列表 #501');
  const rootList = rls[0] || null;
  if (rootList) assert.equal(rootList.sub, null, '/9/#501 根对象列表同时能当消息解析');

  const ents = new Map();
  const order = [];
  for (let index = 0; index < holder.length; index++) {
    const rec = holder[index];
    if (!rec.sub) continue;
    const idF = rec.sub.filter((f) => f.wt === 0 && f.field === 501 && f.num > ID_LO && f.num < ID_HI);
    if (idF.length === 0) continue;
    assert.equal(idF.length, 1, `记录 ${index} 有多个 #501 ID`);
    const id = Number(idF[0].num);
    assert(!ents.has(id), '控件 ID 重复: ' + id);
    const pidF = rec.sub.filter((f) => f.wt === 0 && f.field === 504);
    assert(pidF.length <= 1, `记录 #${id} 有多个 #504`);
    const pid = pidF.length ? Number(pidF[0].num) : null;
    const clF = rec.sub.filter((f) => f.field === 503);
    assert(clF.length <= 1, `记录 #${id} 有多个 #503`);
    let childList = null, childIds = null;
    if (clF.length === 1) {
      const c = clF[0];
      const ids = (c.wt === 2 && !c.isText) ? asIdList(c.payload, true) : null;
      assert(ids !== null, `记录 #${id} 顶层 #503 不是纯 ID 列表`);
      childList = c;
      childIds = ids;
    }
    let name = null;
    for (const t of textsOf(rec.sub, [])) {
      const s = t.payload.toString('utf8');
      if (!KNOWN_TYPES.has(s)) { name = s; break; }
    }
    const e = { id, pid, name, node: rec, index, childList, childIds };
    ents.set(id, e);
    order.push(e);
  }
  return { holder, rootList, ents, order };
}

function nestedIdLists(tree, holder) {
  let n = 0;
  const count = (fields) => {
    for (const f of fields) {
      if (f.field === 503 && f.wt === 2 && !f.isText && asIdList(f.payload, true) !== null) n++;
      if (f.sub) count(f.sub);
    }
  };
  for (const f of tree) if (f.sub && f.sub !== holder) count(f.sub);
  for (const rec of holder) if (rec.sub) for (const f of rec.sub) if (f.sub) count(f.sub);
  return n;
}

function linkCheck(ents) {
  let mismatch = 0, dangling = 0, parentMissing = 0;
  const detail = [];
  for (const e of ents.values()) {
    if (e.pid === null) continue;
    const p = ents.get(e.pid);
    if (!p) { parentMissing++; detail.push(`parentMissing #${e.id} -> ${e.pid}`); continue; }
    if (!p.childIds || !p.childIds.includes(e.id)) { mismatch++; detail.push(`mismatch #${e.id} -> ${e.pid}`); }
  }
  for (const e of ents.values()) {
    if (!e.childIds) continue;
    for (const cid of e.childIds) {
      const c = ents.get(cid);
      if (!c || c.pid !== e.id) { dangling++; detail.push(`dangling #${e.id} -> #${cid}`); }
    }
  }
  return { mismatch, dangling, parentMissing, detail };
}

function occurrencesOf(tree, ids) {
  const S = ids instanceof Set ? ids : new Set(ids);
  const where = [];
  let n = 0;
  (function scan(fields, p) {
    fields.forEach((f, k) => {
      const here = `${p}/#${f.field}[${k}]`;
      if (f.wt === 0) {
        if (S.has(Number(f.num))) { n++; if (where.length < 10) where.push(`varint ${f.num} @${here}`); }
      } else if (f.wt === 2 && !f.isText && f.len > 0) {
        const list = asIdList(f.payload, true);
        if (list && list.some((x) => S.has(x))) { n++; if (where.length < 10) where.push(`idlist @${here}`); }
      }
      if (f.sub) scan(f.sub, here);
    });
  })(tree, '');
  return { n, where };
}

// 闸 1.5：改动前模型自证
const M0 = buildModel(g.tree);
assert.equal(nestedIdLists(g.tree, M0.holder), 0, '改动前存在嵌套 #503 ID 列表');
const lc0 = linkCheck(M0.ents);
assert.equal(lc0.mismatch + lc0.dangling + lc0.parentMissing, 0, '改动前父子关系不自洽: ' + lc0.detail.join('; '));
const rootIds0 = M0.rootList ? asIdList(M0.rootList.payload, true) : [];
const parentless0 = M0.order.filter((e) => e.pid === null).map((e) => e.id).sort((a, b) => a - b);
assert.deepEqual([...rootIds0].sort((a, b) => a - b), parentless0, '改动前根对象列表与无父记录不一致');

// ═════════════════════════════════════════════════════════════════════════════
// PART B：确定待删除的 872 个失效教程控件并执行级联安全删除
// ═════════════════════════════════════════════════════════════════════════════
const SKIPPED_PAGES = [
  'td.l1.page.2',
  'td.l1.page.4',
  'td.l1.page.5',
  'td.l1.page.6',
  'td.l2.page.1',
];

// 明确保护名单：755 中复用做已完成步对勾的 9 个叠层图片控件（绝对不可误删）
const PROTECTED_OVERLAYS = new Set([
  'td.l1.page.3.stepn.5.bg',
  'td.l1.page.7.stepn.5.bg', 'td.l1.page.7.stepn.6.bg',
  'td.l1.page.8.stepn.5.bg', 'td.l1.page.8.stepn.6.bg', 'td.l1.page.8.stepn.7.bg',
  'td.l2.page.3.stepn.4.bg',
  'td.l2.page.4.step.4', 'td.l2.page.4.stepn.4.bg',
]);

const byId49 = new Map(g749.recs.map((r) => [r.id, r]));
const delIds = new Set();
const stat = {
  beforeEntities: M0.ents.size,
  skippedPageSubtrees: {},
  skippedPageTotal: 0,
  hiddenLeavesByPage: {},
  hiddenLeavesTotal: 0,
  totalDeleted: 0,
  parentListsEdited: 0,
};

// 1) 收集 5 个废弃页面的整棵子树
for (const sp of SKIPPED_PAGES) {
  const r = g.byName.get(sp);
  assert(r, '缺少待删除废弃教程页: ' + sp);
  const stack = [r.id];
  let cnt = 0;
  while (stack.length) {
    const id = stack.pop();
    if (delIds.has(id)) continue;
    const e = M0.ents.get(id);
    assert(e, '实体不存在: #' + id);
    assert(!PROTECTED_OVERLAYS.has(e.name), '保护控件不得被删: ' + e.name);
    delIds.add(id);
    cnt++;
    for (const cid of (e.childIds || [])) stack.push(cid);
  }
  stat.skippedPageSubtrees[sp] = cnt;
  stat.skippedPageTotal += cnt;
}

// 2) 收集 8 个保留教程页下从 749v8 到 755 新增失效隐藏的叶控件
const ACTIVE_PAGES = new Set([
  'td.home.page.1',
  'td.l1.page.1', 'td.l1.page.3', 'td.l1.page.7', 'td.l1.page.8',
  'td.l2.page.2', 'td.l2.page.3', 'td.l2.page.4',
]);

for (const r55 of g.recs) {
  if (delIds.has(r55.id)) continue;
  const r49 = byId49.get(r55.id);
  if (!r49) continue;
  if (!isHidden(r49) && isHidden(r55)) {
    const nm = r55.name || '';
    const pagePrefix = nm.split('.').slice(0, 4).join('.');
    assert(ACTIVE_PAGES.has(pagePrefix), '发现非预期页面下新增隐藏控件: ' + nm);
    assert(!PROTECTED_OVERLAYS.has(nm), '保护控件不应处于隐藏状态: ' + nm);
    const e = M0.ents.get(r55.id);
    assert(!e.childIds || e.childIds.length === 0, '新增隐藏叶控件意外带有子控件: ' + nm);
    delIds.add(r55.id);
    stat.hiddenLeavesByPage[pagePrefix] = (stat.hiddenLeavesByPage[pagePrefix] || 0) + 1;
    stat.hiddenLeavesTotal++;
  }
}

stat.totalDeleted = delIds.size;
assert.equal(stat.skippedPageTotal, 731, `废弃整页控件数预期 731，实际 ${stat.skippedPageTotal}`);
assert.equal(stat.hiddenLeavesTotal, 141, `保留页失效叶控件数预期 141，实际 ${stat.hiddenLeavesTotal}`);
assert.equal(stat.totalDeleted, 872, `总清理控件数预期 872，实际 ${stat.totalDeleted}`);

// 确认被删对象里没有任何根对象
for (const id of delIds) {
  assert(M0.ents.get(id).pid !== null, '拒绝删除根对象: #' + id);
}

// 执行删除：① 从未被删除的父记录顶层 #503 列表摘除 ID
for (const id of delIds) {
  const e = M0.ents.get(id);
  if (delIds.has(e.pid)) continue;
  const p = M0.ents.get(e.pid);
  assert(p && p.childList, `父 #${e.pid} 缺少顶层 #503`);
  const at = p.childIds.indexOf(id);
  assert(at >= 0, `父 #${p.id} 的 #503 列表缺少子 #${id}`);
  p.childIds.splice(at, 1);
  setChildList(p.childList, p.childIds);
  p.childList.sub = null;
  stat.parentListsEdited++;
}

// ② 从 /9 容器摘除被删记录
const delNodes = new Set([...delIds].map((id) => M0.ents.get(id).node));
const keepHolder = M0.holder.filter((f) => !delNodes.has(f));
assert.equal(M0.holder.length - keepHolder.length, delIds.size, '容器摘除数量不匹配');
M0.holder.splice(0, M0.holder.length, ...keepHolder);

// ═════════════════════════════════════════════════════════════════════════════
// PART C：内嵌脚本同步清理（静态路径表去掉 5 废页 + _paint 只遍历有效映射页）
// ═════════════════════════════════════════════════════════════════════════════
const leaf = findScriptLeaf(g);
const original = leaf.buf.toString('utf8');
let lua = original;

function replaceOnce(label, from, to) {
  const idx = lua.indexOf(from);
  assert(idx !== -1, `补丁 [${label}] 锚点未找到`);
  assert(lua.indexOf(from, idx + from.length) === -1, `补丁 [${label}] 锚点出现多次，拒绝替换`);
  lua = lua.slice(0, idx) + to + lua.slice(idx + from.length);
}

// 1) 静态路径表移除已删除的 5 个废弃教程页，避免静态路径表指向不存在的控件
replaceOnce(
  'static_paths_td_l1_l2',
  `  add("root/td.l1", [=[td.l1.page.1
td.l1.page.2
td.l1.page.3
td.l1.page.4
td.l1.page.5
td.l1.page.6
td.l1.page.7
td.l1.page.8]=])
  add("root/td.l2", [=[td.l2.page.1
td.l2.page.2
td.l2.page.3
td.l2.page.4]=])`,
  `  add("root/td.l1", [=[td.l1.page.1
td.l1.page.3
td.l1.page.7
td.l1.page.8]=])
  add("root/td.l2", [=[td.l2.page.2
td.l2.page.3
td.l2.page.4]=])`
);

// 2) tutorial_ui:M:_paint() 仅遍历 page_map 中的实际存在页，彻底消除对已删页的查找 miss
replaceOnce(
  'tutorial_paint_only_existing_pages',
  `  local total_raw = self.raw_pages or self.pages
  for r = 1, total_raw do
    self:_visible(self.root_name .. ".page." .. tostring(r), r == cur_raw)
  end`,
  `  if self.page_map ~= nil then
    for i = 1, #self.page_map do
      local r = self.page_map[i]
      self:_visible(self.root_name .. ".page." .. tostring(r), r == cur_raw)
    end
  else
    local total_raw = self.raw_pages or self.pages
    for r = 1, total_raw do
      self:_visible(self.root_name .. ".page." .. tostring(r), r == cur_raw)
    end
  end`
);

// 3) 更新构建标记为 v756
replaceOnce(
  'build_marker_1',
  'if print then print("[murdoku] ===== 构建标记 v755 / 教程图文间距与视觉一致性精修 =====") end',
  'if print then print("[murdoku] ===== 构建标记 v756 / 清理失效教程控件 =====") end'
);
replaceOnce(
  'build_marker_2',
  'print("[murdoku] ===== 构建标记 v755 / 教程图文间距与视觉一致性精修 =====")',
  'print("[murdoku] ===== 构建标记 v756 / 清理失效教程控件 =====")'
);

// ═════════════════════════════════════════════════════════════════════════════
// PART D：静态门禁 + writeGil 写盘回读 + 全图双向一致性与零残留闸门
// ═════════════════════════════════════════════════════════════════════════════
const baseLuaTmp = path.join(runTmp, 'base755.lua');
const candLuaTmp = path.join(runTmp, 'cand756.lua');
fs.writeFileSync(baseLuaTmp, original, 'utf8');
fs.writeFileSync(candLuaTmp, lua, 'utf8');

function luacGlobals(filePath) {
  const r = spawnSync('luac', ['-p', '-l', filePath], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  assert.equal(r.status, 0, `luac 语法检查失败 (${filePath}):\n${r.stderr}`);
  const gets = new Set(), sets = new Set();
  for (const line of r.stdout.split(/\r?\n/)) {
    const gm = line.match(/GETTABUP\s+.*_ENV\s+"([^"]+)"/);
    if (gm) gets.add(gm[1]);
    const sm = line.match(/SETTABUP\s+.*_ENV\s+"([^"]+)"/);
    if (sm) sets.add(sm[1]);
  }
  return { gets, sets };
}

const gBase = luacGlobals(baseLuaTmp);
const gCand = luacGlobals(candLuaTmp);
const newGets = [...gCand.gets].filter((x) => !gBase.gets.has(x));
const newSets = [...gCand.sets].filter((x) => !gBase.sets.has(x));
assert.deepEqual(newGets, [], '禁止新增隐式全局读: ' + newGets.join(', '));
assert.deepEqual(newSets, [], '禁止新增隐式全局写: ' + newSets.join(', '));
console.log(`STATIC_GATE_OK: newGets=0 newSets=0 scriptBytes=${Buffer.byteLength(original, 'utf8')}->${Buffer.byteLength(lua, 'utf8')}`);

leaf.field.payload = Buffer.from(lua, 'utf8');
const stageGil = path.join(runTmp, '756_stage.gil');
const writeReport = writeGil(g, stageGil, {
  label: '756 清理失效教程控件',
  expectRecs: g.recs.length - delIds.size,
  expectMarker: 'v756',
  assert: (gBack) => {
    const M1 = buildModel(gBack.tree);
    assert.equal(M1.ents.size, M0.ents.size - delIds.size, `回读实体数应为 ${M0.ents.size - delIds.size}，实际 ${M1.ents.size}`);
    assert.equal(nestedIdLists(gBack.tree, M1.holder), 0, '回读出现嵌套 #503 ID 列表');
    const lc1 = linkCheck(M1.ents);
    assert.equal(lc1.mismatch + lc1.dangling + lc1.parentMissing, 0, '回读父子关系不自洽: ' + lc1.detail.join('; '));
    const occ = occurrencesOf(gBack.tree, delIds);
    assert.equal(occ.n, 0, `被删 ID 在文件中仍有 ${occ.n} 处残留: ${occ.where.join(', ')}`);
    const rootIds1 = M1.rootList ? asIdList(M1.rootList.payload, true) : [];
    const parentless1 = M1.order.filter((e) => e.pid === null).map((e) => e.id).sort((a, b) => a - b);
    assert.deepEqual([...rootIds1].sort((a, b) => a - b), parentless1, '回读根对象列表与无父记录不一致');

    // 回读确认单人配置 Top#11 原样保留
    const t11Out = gBack.tree.find((x) => x.field === 11);
    assert.equal(t11Out.sub.find((x) => x.field === 6).sub[0].sub.find((x) => x.field === 502).num, 1n, '单人分组人数上限不是 1');
    assert.equal(t11Out.sub.find((x) => x.field === 2).sub[0].sub.find((x) => x.field === 4).payload.length, 1, '初始玩家阵营人数不是 1');

    // 回读确认全部 9 个受保护的对勾叠层控件和全部 8 个有效教程页依然存在且非隐藏
    for (const nm of [...PROTECTED_OVERLAYS, ...ACTIVE_PAGES]) {
      const rec = gBack.byName.get(nm);
      assert(rec, '受保护控件回读丢失: ' + nm);
      assert.equal(isHidden(rec), false, '受保护控件意外隐藏: ' + nm);
    }

    // 回读确认已删除的 5 页确实不存在
    for (const sp of SKIPPED_PAGES) {
      assert(!gBack.byName.get(sp), '废弃教程页未被删干净: ' + sp);
    }

    // 回读确认内嵌脚本一致
    assert.equal(findScriptLeaf(gBack).buf.toString('utf8'), lua, '回读内嵌脚本不一致');
    return true;
  },
});

console.log('CLEANUP_STATS_756:', JSON.stringify({
  before: M0.ents.size,
  after: M0.ents.size - delIds.size,
  deleted: delIds.size,
  skippedPageSubtrees: stat.skippedPageSubtrees,
  hiddenLeavesByPage: stat.hiddenLeavesByPage,
  bytesBefore: g.src.length,
  bytesAfter: fs.statSync(stageGil).size,
  bytesSaved: g.src.length - fs.statSync(stageGil).size,
}));

// ═════════════════════════════════════════════════════════════════════════════
// PART E：导出清理后的控件树并执行全套离线高仿真 Lua 回归测试
// ═════════════════════════════════════════════════════════════════════════════
const treePath = path.join(runTmp, 'tree756.lua');
{
  const exp = spawnSync('node', [path.join(repo, 'tests/export_gil_tree.mjs'), stageGil, treePath], { encoding: 'utf8' });
  assert.equal(exp.status, 0, 'export_gil_tree 失败:\n' + exp.stderr + exp.stdout);
  process.stdout.write(exp.stdout);
}

// 1) 冷启动商城渲染回归
{
  const r = spawnSync('lua', [path.join(repo, 'tests/shop_cold_render.lua')], { input: lua, encoding: 'utf8', cwd: repo });
  assert.equal(r.status, 0, 'shop_cold_render 失败:\n' + r.stdout + '\n' + r.stderr);
  process.stdout.write(r.stdout);
}

// 2) 749v8 纸张动画零回归验证
const animJsonPath = path.join(runTmp, 'verify_749_on_756.json');
{
  const r = spawnSync('lua', [path.join(repo, 'tests/verify_749_paper_anim.lua'), treePath, candLuaTmp, animJsonPath], { encoding: 'utf8', cwd: repo });
  assert.equal(r.status, 0, 'verify_749_paper_anim 失败:\n' + r.stdout + '\n' + r.stderr);
  process.stdout.write(r.stdout);
  assert(r.stdout.includes('VERIFY_749_PASS=true'), 'verify_749_paper_anim 未通过');
}

// 3) 756 专项回归测试（全量覆盖 a~j + 清理专项 k）
const feedbackJson = path.join(runTmp, 'verify_756_feedback.json');
{
  const r = spawnSync('lua', [path.join(repo, 'tests/verify_756_feedback.lua'), treePath, candLuaTmp, feedbackJson], { encoding: 'utf8', cwd: repo });
  process.stdout.write(r.stdout);
  assert.equal(r.status, 0, 'verify_756_feedback 失败:\n' + r.stderr + r.stdout);
  assert(r.stdout.includes('VERIFY_756_PASS=true'), 'verify_756_feedback 未通过');
}

// 全部门禁通过后正式落盘 756 新目录（绝不覆盖 750~755 旧档）
const outDir = path.dirname(out);
fs.mkdirSync(outDir, { recursive: true });
fs.copyFileSync(stageGil, out);
const diskBuf = fs.readFileSync(out);
fs.writeFileSync(path.join(outDir, '756_内嵌脚本.lua'), lua, 'utf8');

const report = {
  version: '756',
  base: path.relative(repo, base),
  base_sha256: sha(g.src),
  output: path.relative(repo, out),
  output_bytes: diskBuf.length,
  bytes_saved: g.src.length - diskBuf.length,
  output_sha256: sha(diskBuf),
  records_before: M0.ents.size,
  records_after: M0.ents.size - delIds.size,
  records_deleted: delIds.size,
  cleanup_breakdown: {
    skipped_pages_subtrees: stat.skippedPageSubtrees,
    skipped_pages_total: stat.skippedPageTotal,
    active_pages_hidden_leaves: stat.hiddenLeavesByPage,
    active_pages_hidden_leaves_total: stat.hiddenLeavesTotal,
    parent_lists_edited: stat.parentListsEdited,
  },
  single_player_preserved: { faction_players: 1, group_max_players: 1 },
  globals_gate: { newGets: 0, newSets: 0 },
  verify749PaperAnim: JSON.parse(fs.readFileSync(animJsonPath, 'utf8')),
  feedback_tests: JSON.parse(fs.readFileSync(feedbackJson, 'utf8')),
};
fs.writeFileSync(path.join(outDir, '756_验证与结构报告.json'), JSON.stringify(report, null, 2), 'utf8');

if (!keepTmp) fs.rmSync(runTmp, { recursive: true, force: true });
console.log('BUILD_756_OK:', out, 'bytes=' + diskBuf.length, 'saved=' + report.bytes_saved, 'sha256=' + report.output_sha256);
