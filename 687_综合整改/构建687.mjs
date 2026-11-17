// 687 · 基于 686 真机反馈整改（四项）
//   A 结算倒计时跟随 683 四键换位；B 恢复「未启用结算」变灰染色（683 重建胶囊后 bg 子层丢失）；
//   C 首页网格纸回 656 设计位（48 个共享子层不动，只在 sync_art641 给 home/select 分屏设偏移，game 不变）；
//   D 三套教程弹窗右上角小叉统一成提示弹窗的 20×20，点击热区同步放大 Δ。
//   用法 FORCE=1 node 构建687.mjs   /   node 构建687.mjs --dry
//
// ★ 口径：旧 .gil 记录只改 7 条（1 倒计时 + 6 小叉/热区）；内嵌 Lua 两处补丁可反向还原；
//         网格纸静态层逐字节不变，分屏靠真机 sync_art641() 的 SetAnchoredPosition（680 已证实该覆盖生效）。
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const REPO = path.join(ROOT, 'qianxing-murdoku');
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '687_规格.json'), 'utf8'));
const INPUT = path.join(REPO, SPEC.base.file);
const OUTPUT = path.join(DIR, '687_综合整改.gil');
const sha = f => crypto.createHash('sha256').update(fs.readFileSync(f)).digest('hex');
const DRY = process.argv.includes('--dry');
if (fs.existsSync(OUTPUT) && process.env.FORCE !== '1' && !DRY)
  throw Error('输出已存在，迭代请加 FORCE=1：' + OUTPUT);
if (sha(INPUT) !== SPEC.base.sha256) throw Error('输入 SHA256 与规格不符');
const url = p => pathToFileURL(p).href;
const { readGil, encodeMsg, writeVarint, stateBlocks, pairOf, pairValue, setPair,
  ensureChildListTop, findChildListTop, asIdList, setChildList, recordsOf } =
  await import(url(path.join(REPO, 'tools/gil/gilread.mjs')));
const { writeGil, findScriptLeaf } = await import(url(path.join(REPO, 'tools/gil/gilwrite.mjs')));
const { isHiddenRecord } = await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));

const g = readGil(INPUT);
const recTop = g.tree.find(f => f.field === 9);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const R = n => { const r = byName.get(n); if (!r) throw Error('缺控件 ' + n); return r; };
const scriptLeaf = findScriptLeaf(g);
const s0 = scriptLeaf.buf.toString('utf8');
if (Buffer.byteLength(s0) !== SPEC.base.scriptBytes) throw Error('内嵌 Lua 字节数与规格不符');
const beforeBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const danglingBefore = new Set([...byId.keys()].filter(id =>
  byId.get(id).parentId != null && !byId.has(byId.get(id).parentId)));
const changes = [];
const modified = new Set();

// ── 几何工具（沿用 682/683/684 构建器口径） ───────────────────────────────
const states = r => stateBlocks(r.field.sub, []);
function setGeomLocal(r, dx, dyUp, w, h) {
  for (const st of states(r)) {
    const p = pairOf(st, 504), s = pairOf(st, 505);
    if (!p || !s) throw Error('几何字段缺失 ' + r.name);
    setPair(p, dx, dyUp); setPair(s, w, h);
  }
  modified.add(r.name);
}
const geom0 = r => {
  const st = states(r)[0], p = pairOf(st, 504), s = pairOf(st, 505);
  return [pairValue(p, 0), pairValue(p, 1), pairValue(s, 0), pairValue(s, 1)];
};

// ═══════════════════════════════════════════════════════════════════════
// A. 结算倒计时跟随换位：-200 → -95
// ═══════════════════════════════════════════════════════════════════════
{
  const A = SPEC.A_countdown, r = R(A.name);
  const [x, y, w, h] = geom0(r);
  if (Math.abs(y - A.fromY) > 0.01) throw Error('倒计时基准不符 ' + y);
  setGeomLocal(r, x, A.toY, w, h);
  changes.push({ name: A.name, rule: 'A 跟随 683 四键整体 -108 换位', from: [x, y, w, h], to: [x, A.toY, w, h] });
}

// ═══════════════════════════════════════════════════════════════════════
// D. 小叉统一（提示弹窗 = hint635.*，20×20）+ 热区同步放大 Δ
// ═══════════════════════════════════════════════════════════════════════
{
  const D = SPEC.D_close;
  // 基准组逐条核对（不改动）
  for (const n of ['hint635.menu.close', 'hint635.result.close', 'help617.close']) {
    const [, , w, h] = geom0(R(n));
    if (Math.abs(w - D.targetX) > 1e-6 || Math.abs(h - D.targetX) > 1e-6)
      throw Error('提示弹窗小叉基准不符 ' + n + ' ' + w + 'x' + h);
  }
  for (const n of ['hint635.menu.close.hit', 'hint635.result.close.hit', 'help617.close.hit']) {
    const [, , w, h] = geom0(R(n));
    if (Math.abs(w - 36) > 1e-6 || Math.abs(h - 36) > 1e-6) throw Error('提示弹窗热区基准不符 ' + n);
  }
  for (const page of ['home', 'l1', 'l2']) {
    const xn = 'td.' + page + '.closex', hn = 'td.' + page + '.btn.close';
    const xr = R(xn), hr = R(hn);
    const [xx, xy, xw, xh] = geom0(xr), [hx, hy, hw, hh] = geom0(hr);
    if (Math.abs(xw - D.xFrom) > 1e-6 || Math.abs(xh - D.xFrom) > 1e-6) throw Error('教程小叉基准不符 ' + xn);
    if (Math.abs(hw - D.hitFrom) > 1e-6 || Math.abs(hh - D.hitFrom) > 1e-6) throw Error('教程热区基准不符 ' + hn);
    setGeomLocal(xr, xx, xy, D.targetX, D.targetX);
    setGeomLocal(hr, hx, hy, D.hitTo, D.hitTo);
    changes.push({ name: xn, rule: 'D 右上角小叉统一到提示弹窗 20×20', from: [xx, xy, xw, xh], to: [xx, xy, D.targetX, D.targetX] });
    changes.push({ name: hn, rule: 'D 点击热区同步放大 Δ=' + D.hitDelta.toFixed(6), from: [hx, hy, hw, hh], to: [hx, hy, D.hitTo, D.hitTo] });
  }
  // 没有小叉的弹窗（modal / result / win…）：用户「没有的忽略」⇒ 不新增
}

// ═══════════════════════════════════════════════════════════════════════
// B + C. 内嵌 Lua 两处补丁
// ═══════════════════════════════════════════════════════════════════════
const P_B_FROM = `  elseif key == "enabled" then
    if ctrl.interactable ~= nil then ctrl.interactable = value and true or false end
    if id == "result.settle" or id == "modal.settle" then
      local bg = self:sub(id, "bg")
      if bg then bg.imageColor = value and 0xFFFFFFFF or 0xFF686B70 end
    end`;
const P_B_TO = `  elseif key == "enabled" then
    if ctrl.interactable ~= nil then ctrl.interactable = value and true or false end
    if id == "result.settle" or id == "modal.settle" then
      local bg = self:sub(id, "bg")
      if bg then bg.imageColor = value and 0xFFFFFFFF or 0xFF686B70 end
      -- ★ 687：682/683 把胶囊与描边收进名为 art 的 DECOR 容器后，bg 子层已不存在，
      --   上面的染色够不到按钮 ⇒ 未启用结算时不再变灰。这里沿 art 容器逐层恢复/置灰。
      --   颜色口径：启用 outline=#FF6C402E / capsule=#FFFCECD4；禁用统一 #FF686B70。
      local art = self:sub(id, "art")
      if art ~= nil then
        local kids = nil
        pcall(function() kids = art:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, #kids do
            local k = kids[i]
            if k ~= nil then
              local nm = nil
              pcall(function() nm = k.name end)
              local outline = (type(nm) == "string" and nm:find("outline") ~= nil)
              pcall(function()
                if k.imageColor ~= nil then
                  k.imageColor = value and (outline and 0xFF6C402E or 0xFFFCECD4) or 0xFF686B70
                end
              end)
            end
          end
        end
      end
    end`;

const P_C_FROM = `        local dx, dy = 0, 0
        if screen == "game" then dx, dy = 105, 46 end`;
const P_C_TO = `        -- ★ 687：art657.grid.reuse 一套 48 层被 home / game 两屏共享。680 为让关卡内
        --   网格纸跟随棋盘下移，把全部子层各 -30 ⇒ 首页被连带额外下移（656 设计位 -5 → 686 -45.5）。
        --   静态层保持不动（game 屏位置不变），只给 home/select 的父容器 +40.5 把首页抬回设计位；
        --   game 分支 (105,46) 逐字不动 ⇒ 两处真正分开调整。
        local dx, dy = 0, 40.5
        if screen == "game" then dx, dy = 105, 46 end`;

const PATCHES = [
  { tag: 'settle_tint', from: P_B_FROM, to: P_B_TO },
  { tag: 'grid_home_dy', from: P_C_FROM, to: P_C_TO },
];
let s1 = s0;
for (const p of PATCHES) {
  const n = s1.split(p.from).length - 1;
  if (n !== 1) throw Error('内嵌 Lua 锚点不唯一/缺失 [' + p.tag + '] 出现 ' + n + ' 次');
  s1 = s1.replace(p.from, p.to);
}
let rev = s1;
for (const p of [...PATCHES].reverse()) {
  const n = rev.split(p.to).length - 1;
  if (n !== 1) throw Error('反向锚点不唯一 [' + p.tag + ']');
  rev = rev.replace(p.to, p.from);
}
if (rev !== s0) throw Error('内嵌 Lua 补丁不干净（反向替换未还原 686）');
scriptLeaf.field.payload = Buffer.from(s1, 'utf8');
scriptLeaf.field.len = Buffer.byteLength(s1);
fs.writeFileSync(path.join(DIR, '687_内嵌Lua_686.lua'), s0, 'utf8');
fs.writeFileSync(path.join(DIR, '687_内嵌Lua_687.lua'), s1, 'utf8');

// ═══════════════════════════════════════════════════════════════════════
// 源码同步（幂等；CRLF 自适应；--dry 不落盘）
// ═══════════════════════════════════════════════════════════════════════
const crlf = t => t.replace(/\n/g, '\r\n');
const sourceSync = [];
{
  const file = 'lua/engine_adapter_qianxing.lua';
  const p = path.join(REPO, file);
  let src = fs.readFileSync(p, 'utf8');
  if (src.includes('★ 687')) {
    sourceSync.push({ file, status: 'already-patched' });
  } else {
    const from = `  elseif key == "enabled" then
    if ctrl.interactable ~= nil then ctrl.interactable = value and true or false end`;
    const to = from + `
    -- ★ 687：未启用结算时，沿按钮 art 容器把 6 层胶囊/描边一并染灰（682/683 后 bg 子层已不存在）。
    if id == "result.settle" or id == "modal.settle" then
      local art = self:sub(id, "art")
      if art ~= nil then
        local kids = nil
        pcall(function() kids = art:GetChildren() end)
        if type(kids) == "table" then
          for i = 1, #kids do
            local k = kids[i]
            if k ~= nil then
              local nm = nil
              pcall(function() nm = k.name end)
              local outline = (type(nm) == "string" and nm:find("outline") ~= nil)
              pcall(function()
                if k.imageColor ~= nil then
                  k.imageColor = value and (outline and 0xFF6C402E or 0xFFFCECD4) or 0xFF686B70
                end
              end)
            end
          end
        end
      end
    end`;
    const eol = src.includes('\r\n') ? crlf : (t => t);
    const a = eol(from), b = eol(to);
    const n = src.split(a).length - 1;
    if (n !== 1) throw Error('源码 enabled 锚点不唯一 ' + n);
    src = src.replace(a, b);
    if (!DRY) fs.writeFileSync(p, src, 'utf8');
    sourceSync.push({ file, status: DRY ? 'dry-patched' : 'patched', patches: ['settle_tint'] });
  }
}
{
  const file = 'lua/entry_client_script.lua';
  const p = path.join(REPO, file);
  let src = fs.readFileSync(p, 'utf8');
  if (src.includes('★ 687 网格纸')) {
    sourceSync.push({ file, status: 'already-patched' });
  } else {
    const anchor = '        --   8×8 组标记；并用 _mark_screen_on 门控挡住切屏瞬间的 x_mark 抢先点亮。';
    if (src.split(anchor).length - 1 !== 1) throw Error('entry 686 注释锚点不唯一');
    const E = src.includes('\r\n') ? '\r\n' : '\n';
    src = src.replace(anchor, anchor + E
      + '        -- ★ 687 网格纸双屏分开：art657.grid.reuse 48 层由 home / game 共享，静态层不再改；' + E
      + '        --   sync_art641() 里 home/select 父偏移 (0,40.5) 回 656 设计位，game 仍 (105,46)。');
    if (!DRY) fs.writeFileSync(p, src, 'utf8');
    sourceSync.push({ file, status: DRY ? 'dry-patched' : 'patched', patches: ['grid_note'] });
  }
}

// ═══════════════════════════════════════════════════════════════════════
// 闸门
// ═══════════════════════════════════════════════════════════════════════
g.recs = recordsOf(g.tree);
const idsNow = new Set(g.recs.map(r => r.id));
for (const r of g.recs) if (r.parentId != null && !idsNow.has(r.parentId) && !danglingBefore.has(r.id))
  throw Error('新增悬空父引用 ' + r.name);
const afterBytes = new Map(g.recs.map(r => [r.id, encodeMsg([r.field])]));
const changedOld = [...beforeBytes.keys()].filter(id =>
  afterBytes.has(id) && !beforeBytes.get(id).equals(afterBytes.get(id)));
const allowed = new Set(SPEC.D_close.scope.map(n => R(n).id));
allowed.add(R(SPEC.A_countdown.name).id);
const rogue = changedOld.filter(id => !allowed.has(id));
if (rogue.length) throw Error('存在非预期旧记录改动：' + rogue.slice(0, 8).map(id => byId.get(id)?.name || id).join(','));
if (changedOld.length !== 7) throw Error('旧记录改动应为 7 条，实际 ' + changedOld.length);
if (g.recs.length !== SPEC.base.records) throw Error('记录数不符');
// 网格纸共享层逐字节不变
const reuse = R('art657.grid.reuse');
const gridKids = g.recs.filter(r => r.parentId === reuse.id);
if (gridKids.length !== 48) throw Error('网格纸子层数应为 48，实际 ' + gridKids.length);
for (const k of gridKids) if (!beforeBytes.get(k.id).equals(afterBytes.get(k.id)))
  throw Error('网格纸静态子层被改动 ' + k.name);
if (!beforeBytes.get(reuse.id).equals(afterBytes.get(reuse.id))) throw Error('网格纸父层被改动');
// 结算按钮 art 容器恰好 6 层
for (const pn of ['modal.settle', 'result.settle']) {
  const p = R(pn);
  const art = g.recs.find(r => r.name === 'art' && r.parentId === p.id);
  const kids = g.recs.filter(r => r.parentId === art.id);
  if (kids.length !== 6 || kids.some(k => !/capsule|outline/.test(k.name)))
    throw Error('art 容器子层异常 ' + pn);
}
// 几何落点
if (Math.abs(geom0(R(SPEC.A_countdown.name))[1] - SPEC.A_countdown.toY) > 1e-6) throw Error('倒计时落点不符');
for (const n of ['td.home.closex', 'td.l1.closex', 'td.l2.closex']) {
  const [, , w, h] = geom0(R(n));
  if (Math.abs(w - SPEC.D_close.targetX) > 1e-6 || Math.abs(h - SPEC.D_close.targetX) > 1e-6) throw Error('小叉未统一 ' + n);
}
for (const n of ['td.home.btn.close', 'td.l1.btn.close', 'td.l2.btn.close']) {
  const [, , w, h] = geom0(R(n));
  if (Math.abs(w - SPEC.D_close.hitTo) > 1e-6 || Math.abs(h - SPEC.D_close.hitTo) > 1e-6) throw Error('热区未同步放大 ' + n);
}

if (DRY) {
  console.log(JSON.stringify({ dry: true, records: g.recs.length, changedOld: changedOld.length,
    rogue: rogue.length, gridStaticChanged: 0, script: [s0.length, s1.length], sourceSync }, null, 2));
  process.exit(0);
}

const report = writeGil(g, OUTPUT, {
  label: '687 countdown follow + settle disabled tint + home grid paper design pos + unified close X',
  expectRecs: g.recs.length,
  assert(t) {
    const ids = new Set(t.recs.map(r => r.id));
    if (t.recs.length !== g.recs.length) return '记录数不符';
    for (const r of t.recs) {
      const want = afterBytes.get(r.id);
      if (!want || !want.equals(encodeMsg([r.field]))) return '记录回读不符 #' + r.id + ' ' + r.name;
      if (r.parentId != null && !ids.has(r.parentId) && !danglingBefore.has(r.id)) return '新增悬空父引用 ' + r.name;
    }
    if (findScriptLeaf(t).buf.toString('utf8') !== s1) return '内嵌 Lua 变化';
    const rt = t.tree.find(q => q.field === 9);
    const ord = new Map(); rt.sub.forEach((f, i) => ord.set(f, i));
    for (const root of t.recs.filter(q => q.name === 'clue')) {
      const cl = findChildListTop(root.field.sub);
      const list = cl ? (asIdList(cl.payload, true) || []).filter(id => ord.has(t.recs.find(q => q.id === id)?.field)) : [];
      if (list.some((id, i) => i > 0 && ord.get(t.recs.find(q => q.id === list[i - 1]).field) > ord.get(t.recs.find(q => q.id === id).field)))
        return 'childList 与记录表不同序 #' + root.id;
    }
    return true;
  },
});
const audit = {
  version: 687, title: SPEC.title, date: new Date().toISOString().slice(0, 10),
  base: { file: SPEC.base.file, sha256: sha(INPUT), records: beforeBytes.size, scriptBytes: Buffer.byteLength(s0) },
  output: { file: path.basename(OUTPUT), sha256: sha(OUTPUT), bytes: fs.statSync(OUTPUT).size,
    records: g.recs.length, scriptBytes: Buffer.byteLength(s1) },
  spec: SPEC,
  counts: { recordsBefore: beforeBytes.size, recordsAfter: g.recs.length,
    added: 0, removed: 0, changedOldRecords: changedOld.length, rogue: rogue.length,
    gridStaticRecordsChanged: 0, gridSharedChildren: gridKids.length },
  changes, patches: PATCHES.map(p => ({ tag: p.tag, fromBytes: Buffer.byteLength(p.from), toBytes: Buffer.byteLength(p.to) })),
  sourceSync,
  guarantees: SPEC.guarantees,
  writeGilReport: Object.fromEntries(Object.entries(report)
    .filter(([, v]) => v === null || ['string', 'number', 'boolean', 'bigint'].includes(typeof v))),
};
fs.writeFileSync(path.join(DIR, '687_构建审计.json'), JSON.stringify(audit, (k, v) => typeof v === 'bigint' ? v.toString() : v, 2));
fs.writeFileSync(path.join(DIR, '687_逐条变更清单.json'), JSON.stringify(changes, null, 2));
console.log(JSON.stringify({ output: OUTPUT, sha256: audit.output.sha256,
  records: g.recs.length, changedOldRecords: changedOld.length, rogue: rogue.length,
  script: [Buffer.byteLength(s0), Buffer.byteLength(s1)], sourceSync, status: 'APPLIED' }, null, 2));
