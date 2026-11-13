// 686 · 通用性验证：复用 685 的家具枚举数学 + 对 686.gil 的结构断言 + 686 离场收起断言
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
const DIR = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(DIR, '../..');
const url = p => pathToFileURL(p).href;
const SPEC685 = JSON.parse(fs.readFileSync(path.join(ROOT, 'qianxing-murdoku/685_多格家具通用层/685_多格家具通用构造规格.json'), 'utf8'));
const SPEC = JSON.parse(fs.readFileSync(path.join(DIR, '686_离场收起规格.json'), 'utf8'));
const GIL = path.join(DIR, SPEC.output.file);
const { readGil, stateBlocks, pairOf, pairValue, findChildListTop, asIdList } =
  await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilread.mjs')));
const { findScriptLeaf } = await import(url(path.join(ROOT, 'qianxing-murdoku/tools/gil/gilwrite.mjs')));
const { isHiddenRecord } =
  await import(url(path.join(ROOT, 'qianxing-murdoku-tool/dsh-plugin-qianxing-art-pipeline/src/gil/ops.js')));

// ① 家具枚举（与 685 同一口径，证明 686 没有破坏通用性）
const G = SPEC685.generality, MAXN = SPEC685.markLayer.maxBoard;
let cases = 0, uncovered = 0, maxReach = 0, maxCells = 0;
for (const n of G.boardSizes) for (const kind of G.syntheticKinds)
  for (const span_r of G.spans) for (const span_c of G.spans) for (const scale of G.scaleFactors) {
    const rr = Math.ceil(span_r * scale), cc = Math.ceil(span_c * scale);
    maxReach = Math.max(maxReach, rr, cc);
    for (let ar = 1; ar <= n; ar++) for (let ac = 1; ac <= n; ac++) {
      let cnt = 0;
      for (let r = Math.max(1, ar - rr); r <= Math.min(n, ar + rr); r++)
        for (let c = Math.max(1, ac - cc); c <= Math.min(n, ac + cc); c++) {
          cnt++;
          if (r < 1 || c < 1 || r > MAXN || c > MAXN) uncovered++;
        }
      maxCells = Math.max(maxCells, cnt); cases++;
    }
  }
const generality = { enumeratedCases: cases, maxReachCells: maxReach,
  maxOverlappedCellsPerFurniture: maxCells, markGrid: `${MAXN}x${MAXN}`,
  uncoveredCells: uncovered, allCovered: uncovered === 0 };

// ② 结构断言
const g = readGil(GIL);
const byId = new Map(g.recs.map(r => [r.id, r]));
const byName = new Map(g.recs.filter(r => r.name).map(r => [r.name, r]));
const kidsOf = r => { const cl = findChildListTop(r.field.sub || []); return cl ? (asIdList(cl.payload, true) || []) : []; };
const geom = r => { const st = stateBlocks(r.field.sub, [])[0]; if (!st) return null;
  const p = pairOf(st, 504), z = pairOf(st, 505);
  return { pos: p ? [pairValue(p, 0), pairValue(p, 1)] : null, size: z ? [pairValue(z, 0), pairValue(z, 1)] : null }; };
const stage = byName.get('stage'), ov = byName.get('art685.mark.overlay');
const sk = kidsOf(stage);
let markOk = 0, hiddenOk = 0, strokeOk = 0, rotOk = 0;
for (let r = 1; r <= MAXN; r++) for (let c = 1; c <= MAXN; c++) {
  const base = `art685.mark.${r}.${c}`;
  const m = byName.get(base);
  if (!m || m.parentId !== ov.id) continue;
  markOk++; if (isHiddenRecord(m.field)) hiddenOk++;
  const names = kidsOf(m).map(id => byId.get(id)?.name);
  const s0 = byName.get(base + '.stroke.0'), s1 = byName.get(base + '.stroke.1');
  if (names.length === 2 && s0 && s1) {
    strokeOk++;
    if (isHiddenRecord(s0.field) && isHiddenRecord(s1.field)) hiddenOk += 2;
    const rot = [s0, s1].map(s => stateBlocks(s.field.sub, [])[0]?.sub?.find(q => q.field === 508)?.sub?.[0]?.f);
    if (rot.includes(45) && rot.includes(-45)) rotOk++;
  }
}
const s = findScriptLeaf(g).buf.toString('utf8');
const structural = {
  markLayerExists: !!ov,
  markLayerParentIsStage: ov?.parentId === stage.id,
  markLayerIsLastInStage: sk.at(-1) === ov.id,
  overlayPosIsZero: Math.abs(geom(ov).pos[0]) < 0.01 && Math.abs(geom(ov).pos[1]) < 0.01,
  overlaySizeEqualsStage: Math.abs(geom(ov).size[0] - geom(stage).size[0]) < 0.01,
  markContainers: markOk, hiddenRecords: hiddenOk, strokePairs: strokeOk, rotationPairs: rotOk,
  scriptBytes: Buffer.byteLength(s),
  // 686 新增：离场收起
  hasHideAll: s.includes('function Adapter:_mark_hide_all()'),
  hasAllCtrls: s.includes('function Adapter:_mark_all_ctrls()'),
  hasScreenGate: s.includes('if on == true and self._mark_screen_on == false then on = false end'),
  hasStageHook: s.includes('and value ~= true then\n      self:_mark_hide_all()'),
  hasCellHook: s.includes('self:_mark_set_visible(rc, false)'),
  hasHideUnlistedHook: s.includes('if not in_level then self:_mark_hide_all()'),
  // 685 不变式仍在
  stillRaisesEveryFrame: s.includes('self:_mark_layer_raise()'),
  noKindSpecificLayerRule: !/rug_layer.*furn.*SetAsLastSibling|furn_tpl.*SetSiblingIndex/.test(s),
};
const expect = { markLayerExists: true, markLayerParentIsStage: true, markLayerIsLastInStage: true,
  overlayPosIsZero: true, overlaySizeEqualsStage: true, noKindSpecificLayerRule: true,
  hasHideAll: true, hasAllCtrls: true, hasScreenGate: true, hasStageHook: true,
  hasCellHook: true, hasHideUnlistedHook: true, stillRaisesEveryFrame: true };
const errors = Object.entries(expect).filter(([k, v]) => structural[k] !== v).map(([k]) => k);
if (markOk !== 64) errors.push('markContainers');
if (hiddenOk !== 192) errors.push('hiddenRecords');
if (strokeOk !== 64) errors.push('strokePairs');
if (rotOk !== 64) errors.push('rotationPairs');
structural.ok = errors.length === 0;
structural.errors = errors;

const out = { version: 686, verdict: generality.allCovered && structural.ok, generality, structural };
fs.writeFileSync(path.join(DIR, '686_通用性验证.json'), JSON.stringify(out, null, 2));
console.log(JSON.stringify({ verdict: out.verdict, enumeratedCases: cases,
  uncoveredCells: uncovered, markGrid: generality.markGrid,
  markContainers: markOk, hiddenRecords: hiddenOk, strokePairs: strokeOk,
  scriptBytes: structural.scriptBytes, structuralErrors: errors }, null, 2));
if (!out.verdict) process.exitCode = 1;
