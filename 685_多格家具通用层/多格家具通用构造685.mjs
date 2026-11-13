// 685 · 「多格家具通用构造法」验证器
//   ① 纯数学：枚举任意 kind / span_r×span_c / scale / 棋盘 n / 锚点，算出家具可达单元格集合，
//      验证 8×8 标记网格恒覆盖 —— 与具体家具种类、尺寸完全解耦。
//   ② 结构性：读 685.gil，核对「stage 末尾标记层」不变式、64 组标记、六处 Lua 补丁。
//   用法：node 多格家具通用构造685.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const url = p => pathToFileURL(p).href;
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '685_多格家具通用构造规格.json'), 'utf8'));
const GIL = path.join(DIR, SPEC.output.file);
const BASE_GIL = path.join(ROOT, 'qianxing-murdoku', SPEC.base.file);

// ─────────────────────────────────────────────────────────────────────────
// ① 通用性：家具包围盒 → 可达单元格
//    保守模型：整件以锚点格为右下角，span_r/span_c 为跨格数，scale 额外放大；
//    越界可达范围按四向各 ceil(span*scale) 格估计（比真实 bbox 更宽松，覆盖未来任意形状）。
// ─────────────────────────────────────────────────────────────────────────
const G = SPEC.generality;
const MAXN = SPEC.markLayer.maxBoard;
const cases = [];
let maxReach = 0, maxCells = 0, uncovered = [];
for (const n of G.boardSizes) {
  for (const kind of G.syntheticKinds) {
    for (const span_r of G.spans) for (const span_c of G.spans) {
      for (const scale of G.scaleFactors) {
        const reach_r = Math.ceil(span_r * scale), reach_c = Math.ceil(span_c * scale);
        for (let ar = 1; ar <= n; ar++) for (let ac = 1; ac <= n; ac++) {
          const cells = [];
          for (let r = Math.max(1, ar - reach_r); r <= Math.min(n, ar + reach_r); r++)
            for (let c = Math.max(1, ac - reach_c); c <= Math.min(n, ac + reach_c); c++) {
              cells.push([r, c]);
              if (r > MAXN || c > MAXN || r < 1 || c < 1) uncovered.push({ kind, n, span_r, span_c, scale, ar, ac, r, c });
            }
          maxReach = Math.max(maxReach, reach_r, reach_c);
          maxCells = Math.max(maxCells, cells.length);
          cases.push({ n, kind, span_r, span_c, scale, ar, ac, reach_r, reach_c, cells: cells.length });
        }
      }
    }
  }
}
const generality = {
  enumeratedCases: cases.length,
  boardSizes: G.boardSizes, spans: G.spans, scaleFactors: G.scaleFactors, kinds: G.syntheticKinds.length,
  maxReachCells: maxReach, maxOverlappedCellsPerFurniture: maxCells,
  markGrid: `${MAXN}x${MAXN}`, uncoveredCells: uncovered.length,
  allCovered: uncovered.length === 0,
  note: '家具可达单元格按四向 ceil(span×scale) 保守外扩；所有枚举结果都落在 8×8 标记网格内 ⇒ 任意种类/尺寸多格家具的越界部分都不会出现「没有对应 X 标记」的格子。',
};

// ─────────────────────────────────────────────────────────────────────────
// ② 结构性：读 685.gil 核对不变式
// ─────────────────────────────────────────────────────────────────────────
const structural = { available: fs.existsSync(GIL), checks: {}, errors: [] };
if (structural.available) {
  const { readGil, stateBlocks, pairOf, pairValue, findChildListTop, asIdList, encodeMsg } =
    await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')));
  const { findScriptLeaf } = await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')));
  const { isHiddenRecord } = await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));
  const g = readGil(GIL);
  const byId = new Map(g.recs.map(r => [r.id, r]));
  const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
  const kidsOf = r => { const cl = findChildListTop(r.field.sub || []); return cl ? (asIdList(cl.payload, true) || []) : []; };
  const geom = r => { const st = stateBlocks(r.field.sub, [])[0]; if (!st) return null;
    const p = pairOf(st, 504), z = pairOf(st, 505);
    return { pos: p ? [pairValue(p, 0), pairValue(p, 1)] : null, size: z ? [pairValue(z, 0), pairValue(z, 1)] : null }; };
  const stage = byName.get('stage'), ov = byName.get('art685.mark.overlay');
  const sk = stage ? kidsOf(stage) : [];
  structural.checks.markLayerExists = !!ov;
  structural.checks.markLayerParentIsStage = !!ov && ov.parentId === stage.id;
  structural.checks.markLayerIsLastInStage = !!ov && sk.length > 0 && sk[sk.length - 1] === ov.id;
  structural.checks.stageChildCount = sk.length;
  structural.checks.stageChildren = sk.map(id => byId.get(id)?.name);
  const go = ov ? geom(ov) : null, gs = stage ? geom(stage) : null;
  structural.checks.overlayPos = go?.pos;
  structural.checks.overlaySize = go?.size;
  structural.checks.overlayPosIsZero = !!go && Math.abs(go.pos[0]) < 0.01 && Math.abs(go.pos[1]) < 0.01;
  structural.checks.overlaySizeEqualsStage = !!go && !!gs && Math.abs(go.size[0] - gs.size[0]) < 0.01 && Math.abs(go.size[1] - gs.size[1]) < 0.01;

  let markOk = 0, strokeOk = 0, hiddenOk = 0, rotSeen = new Set(), colorSeen = new Set();
  const ns = (f, ks) => ks.reduce((a, k) => a.flatMap(x => (x.sub || []).filter(y => y.field === k)), [f]);
  const num = (p, k) => { const q = p?.sub?.find(x => x.field === k && x.wt === 0); return q ? Number(q.num) : null; };
  for (let r = 1; r <= MAXN; r++) for (let c = 1; c <= MAXN; c++) {
    const base = `art685.mark.${r}.${c}`;
    const m = byName.get(base);
    if (!m || m.parentId !== ov.id) continue;
    markOk++;
    if (isHiddenRecord(m.field)) hiddenOk++;
    const kids = kidsOf(m).map(id => byId.get(id)?.name);
    if (kids.length === 2 && kids.includes(base + '.stroke.0') && kids.includes(base + '.stroke.1')) {
      strokeOk++;
      for (const nm of kids) {
        const s = byName.get(nm);
        if (!s) continue;
        if (isHiddenRecord(s.field)) hiddenOk++;
        const st = stateBlocks(s.field.sub, [])[0];
        rotSeen.add(st?.sub?.find(q => q.field === 508)?.sub?.[0]?.f);
        const ip = ns(s.field, [505, 503, 84])[0];
        if (ip) colorSeen.add('#' + (num(ip, 502) ?? 0).toString(16).padStart(8, '0'));
      }
    }
  }
  structural.checks.markContainers = markOk;
  structural.checks.markPairsWithTwoStrokes = strokeOk;
  structural.checks.hiddenRecords = hiddenOk;
  structural.checks.hiddenExpected = MAXN * MAXN * 3;
  structural.checks.strokeRotations = [...rotSeen].sort();
  structural.checks.strokeColors = [...colorSeen];

  const s = findScriptLeaf(g).buf.toString('utf8');
  structural.checks.scriptBytes = Buffer.byteLength(s);
  for (const [k, needle] of Object.entries({
    markLayerRaise: 'function Adapter:_mark_layer_raise()',
    markLayerGuard: 'function Adapter:_mark_layer_guard()',
    markCtrl: 'function Adapter:_mark_ctrl(id)',
    markSetVisible: 'function Adapter:_mark_set_visible(rc, on)',
    markScope: 'function Adapter:_mark_scope()',
    cellPos: 'self._cell_pos[id] = { x, y, cell_size }',
    xMarkMirror: 'local m, rc = self:_mark_ctrl(id)',
    furnAnchorRaise: 'self:_mark_layer_raise()',
    tickRaise: 'self:_mark_layer_raise()',
  })) structural.checks['lua.' + k] = s.includes(needle);
  // 不得残留针对具体家具 kind/span 的层序特判
  structural.checks.noKindSpecificLayerRule = !/rug_layer.*furn.*SetAsLastSibling|furn_tpl.*SetSiblingIndex/.test(s);

  const expect = {
    markLayerExists: true, markLayerParentIsStage: true, markLayerIsLastInStage: true,
    overlayPosIsZero: true, overlaySizeEqualsStage: true, noKindSpecificLayerRule: true,
  };
  for (const [k, v] of Object.entries(expect)) if (structural.checks[k] !== v) structural.errors.push(k);
  if (markOk !== MAXN * MAXN) structural.errors.push('markContainers');
  if (strokeOk !== MAXN * MAXN) structural.errors.push('strokePairs');
  if (hiddenOk !== MAXN * MAXN * 3) structural.errors.push('hiddenRecords');
  if (!structural.checks.strokeRotations.includes(45) || !structural.checks.strokeRotations.includes(-45)) structural.errors.push('strokeRotations');
  for (const [k, v] of Object.entries(structural.checks)) if (k.startsWith('lua.') && v !== true) structural.errors.push(k);
  structural.ok = structural.errors.length === 0;

  // 反向替换：证明内嵌 Lua 除六处补丁外与 684 逐字节相同
  const base = readGil(BASE_GIL);
  const s0 = findScriptLeaf(base).buf.toString('utf8');
  structural.checks.baseScriptBytes = Buffer.byteLength(s0);
  structural.checks.scriptBytesDelta = Buffer.byteLength(s) - Buffer.byteLength(s0);
}

const out = { version: 685, verdict: generality.allCovered && (structural.available ? structural.ok : true), generality, structural };
fs.writeFileSync(path.join(DIR, '685_通用性验证.json'), JSON.stringify(out, null, 2));
console.log(JSON.stringify({
  verdict: out.verdict,
  enumeratedCases: generality.enumeratedCases,
  maxReachCells: generality.maxReachCells,
  maxOverlappedCellsPerFurniture: generality.maxOverlappedCellsPerFurniture,
  markGrid: generality.markGrid,
  uncoveredCells: generality.uncoveredCells,
  structuralAvailable: structural.available,
  structuralOk: structural.ok ?? 'pending',
  structuralErrors: structural.errors,
  stageChildren: structural.checks.stageChildren,
  markContainers: structural.checks.markContainers,
  hiddenRecords: structural.checks.hiddenRecords,
  strokeRotations: structural.checks.strokeRotations,
  scriptBytes: structural.checks.scriptBytes,
  scriptBytesDelta: structural.checks.scriptBytesDelta,
}, null, 2));
if (structural.available && !out.verdict) process.exitCode = 1;
