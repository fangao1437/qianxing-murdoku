// tools/build_754.mjs
// 基于已配置好单人人数的 753_教程细节与已通重提修复/753.gil 构建 754_教程文本防截断与视觉精修.gil
// 严格不覆盖旧档（750/751/752/753 均保留原样），且完全保留 753.gil 中用户配置的单人房间人数设置（Top#11 等非 UI 字段零触碰）。
//
// 本次 754 专项修复：
// 1. 全面根治全部 8 个教程页（含首页）的文本截断/缺失问题：
//    - 根因：千星客户端 Text 组件左右存在约 10px 内边距，且遇空格会整段 word-wrap 折行裁切；753 给图文混排前置文本和短词（撤销/提交）预留宽度偏窄，且 td.l2.page.4.cluesay.0 沿用了 749 旧宽 336px。
//    - 修复：采用经实机 1604x960 像素反推校准的 safeSingleLineWidth()（含 20px 内边距与防折行余量），重排全部 9 行图文混排、放宽 td.l2.page.4.cluesay.0（336→600）、各页 tag/caption/lgt 宽度，并加入全量 8 页可见单行文本宽度门禁，杜绝任何漏网截断。
// 2. 统一「撤销」及行内操作按钮名文字染色：
//    - 修复 td.home.page.1 与 td.l1.page.3 中「撤销」单独被染成红色（#B82914）而相邻「重做」为深墨黑棕（#231108）的不一致问题；统一将行内按钮名（撤销、重做、提交、提示）改为一致的深墨黑棕 C_INK。
// 3. 修复顶部步骤条已完成步「绿勾左侧出头太少、不明显」：
//    - 根因：原神字体渲染 Unicode 字符「✓」左侧短撇极短（仅 1~2px），缩在 26x26 绿圆里像斜杠。
//    - 修复：将全部已完成步骤（isDone）的 stepn.i.bg 切换为官方标准粗体对勾贴图 100102（22x22，鲜翠绿 #7FE05A），并隐藏对应的 stepn.i 字符，左右勾角清晰对称、对比度充足。
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { stateBlocks, pairOf, pairValue, setPair } from './gil/gilread.mjs';
import { loadTree, findScriptLeaf, writeGil } from './gil/gilwrite.mjs';

const repo = fileURLToPath(new URL('../', import.meta.url));
const runTmp = fs.mkdtempSync(path.join(os.tmpdir(), 'murdoku-754-'));
const keepTmp = process.argv.includes('--keep-tmp');
const overwrite = process.argv.includes('--overwrite');

const base = path.join(repo, '753_教程细节与已通重提修复/753.gil');
const out = path.resolve(
  process.argv[2] && !process.argv[2].startsWith('--')
    ? process.argv[2]
    : path.join(repo, '754_教程文本防截断与视觉精修/754_教程文本防截断与视觉精修.gil')
);

if (!overwrite) assert(!fs.existsSync(out), '输出已存在，拒绝覆盖旧档（本项目习惯按版本号递增导出）：' + out);

const sha = (b) => createHash('sha256').update(b).digest('hex');
const g = loadTree(base);
assert.equal(
  sha(g.src),
  '085afd363b57da3583ffc36086cd7040186f353e7bc56ecd29179d9bd023cedd',
  '基准 753.gil（已配置单人人数）SHA256 不匹配'
);

// ═════════════════════════════════════════════════════════════════════════════
// 辅助函数
// ═════════════════════════════════════════════════════════════════════════════
const ARGB = (hex) => BigInt((0xFF000000 | parseInt(hex.replace('#', ''), 16)) >>> 0);

const stat = {
  tutTexts: 0,
  tutIcons: 0,
  tutRects: 0,
  tutCheckmarks: 0,
  tutHidden: 0,
  checkedTexts: 0,
};

function getTextComp(rec) {
  for (const f of rec.field.sub) {
    if (f.field === 505 && f.sub) {
      const s = f.sub.find((x) => x.field === 503 && x.sub);
      const t75 = s && s.sub.find((x) => x.field === 75 && x.sub);
      if (t75) return t75;
    }
  }
  return null;
}

function getImgComp(rec) {
  for (const f of rec.field.sub) {
    if (f.field === 505 && f.sub) {
      const s = f.sub.find((x) => x.field === 503 && x.sub);
      const c84 = s && s.sub.find((x) => x.field === 84 && x.sub);
      if (c84) return c84;
    }
  }
  return null;
}

function setImgProps(rec, { color, sprite }) {
  if (!rec) return false;
  const c84 = getImgComp(rec);
  if (!c84) return false;
  let changed = false;
  const setVar = (fid, bval) => {
    let f = c84.sub.find((y) => y.field === fid && y.wt === 0);
    if (f) {
      if (f.num !== bval) { f.num = bval; changed = true; }
    } else {
      c84.sub.push({ field: fid, wt: 0, num: bval });
      changed = true;
    }
  };
  if (color !== undefined) setVar(502, ARGB(color));
  if (sprite !== undefined) setVar(503, BigInt(sprite));
  return changed;
}

function setTextProps(rec, { text, size, minSize, color, alignH }) {
  if (!rec) return false;
  const t75 = getTextComp(rec);
  if (!t75) return false;
  let changed = false;
  if (text !== undefined) {
    let t510 = t75.sub.find((y) => y.field === 510);
    if (!t510) {
      t510 = { field: 510, wt: 2, sub: [{ field: 501, wt: 2, isText: true, sub: null, payload: Buffer.alloc(0), len: 0 }] };
      t75.sub.push(t510);
    } else if (!t510.sub) {
      t510.wt = 2;
      t510.sub = [{ field: 501, wt: 2, isText: true, sub: null, payload: Buffer.alloc(0), len: 0 }];
      delete t510.payload;
      changed = true;
    }
    let t501 = t510.sub.find((y) => y.field === 501);
    if (!t501) {
      t501 = { field: 501, wt: 2, isText: true, sub: null, payload: Buffer.alloc(0), len: 0 };
      t510.sub.push(t501);
    }
    const nextBuf = Buffer.from(String(text), 'utf8');
    if (!t501.payload || !t501.payload.equals(nextBuf)) {
      t501.payload = nextBuf;
      t501.len = nextBuf.length;
      t501.isText = true;
      changed = true;
    }
  }
  const setVar = (fid, val) => {
    if (val === undefined) return;
    const bval = BigInt(val);
    let f = t75.sub.find((y) => y.field === fid && y.wt === 0);
    if (f) {
      if (f.num !== bval) { f.num = bval; changed = true; }
    } else {
      t75.sub.push({ field: fid, wt: 0, num: bval });
      changed = true;
    }
  };
  if (size !== undefined) setVar(512, size);
  if (minSize !== undefined) setVar(513, minSize);
  else if (size !== undefined) setVar(513, Math.max(12, size - 2));
  if (color !== undefined) setVar(504, ARGB(color));
  if (alignH === 0) {
    const before = t75.sub.length;
    t75.sub = t75.sub.filter((y) => !(y.field === 508 && y.wt === 0));
    if (t75.sub.length !== before) changed = true;
  } else if (alignH !== undefined) {
    setVar(508, alignH);
  }
  return changed;
}

function getTextInfo(rec) {
  const t75 = getTextComp(rec);
  if (!t75) return null;
  const t510 = t75.sub.find((y) => y.field === 510 && y.sub);
  const t501 = t510 && t510.sub.find((y) => y.field === 501);
  const text = t501 && t501.payload ? t501.payload.toString('utf8') : '';
  const f512 = t75.sub.find((y) => y.field === 512 && y.wt === 0);
  const f504 = t75.sub.find((y) => y.field === 504 && y.wt === 0);
  return {
    text,
    size: f512 ? Number(f512.num) : 20,
    color: f504 ? Number(f504.num) >>> 0 : null,
  };
}

function setRectAllStates(rec, pos, size) {
  if (!rec) return false;
  const bl = [];
  stateBlocks(rec.field.sub, bl);
  if (!bl.length) return false;
  for (const b of bl) {
    if (pos) {
      const p = pairOf(b, 504);
      if (p) setPair(p, pos[0], pos[1]);
    }
    if (size) {
      const s = pairOf(b, 505);
      if (s) setPair(s, size[0], size[1]);
    }
  }
  stat.tutRects++;
  return true;
}

function getRect(rec) {
  const bl = [];
  stateBlocks(rec.field.sub, bl);
  const p = pairOf(bl[0], 504);
  const s = pairOf(bl[0], 505);
  return {
    x: pairValue(p, 0),
    y: pairValue(p, 1),
    w: pairValue(s, 0),
    h: pairValue(s, 1),
  };
}

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

function setHidden(rec, hide = true) {
  if (!rec) return false;
  for (const f of rec.field.sub) {
    if (f.field !== 505 || !f.sub) continue;
    const s = f.sub.find((x) => x.field === 503 && x.sub);
    if (!s) continue;
    const c14 = s.sub.find((x) => x.field === 14 && x.sub);
    if (!c14) continue;
    const c17 = c14.sub.find((x) => x.field === 17);
    if (!c17) continue;
    if (hide) {
      if (!c17.sub) {
        c17.sub = [{ field: 503, wt: 0, num: 1n }];
        delete c17.payload;
        stat.tutHidden++;
        return true;
      }
      const f503 = c17.sub.find((y) => y.field === 503 && y.wt === 0);
      if (!f503) {
        c17.sub.push({ field: 503, wt: 0, num: 1n });
        stat.tutHidden++;
        return true;
      }
      if (f503.num !== 1n) { f503.num = 1n; stat.tutHidden++; return true; }
      return false;
    } else {
      if (c17.sub) {
        c17.sub = c17.sub.filter((y) => y.field !== 503);
        if (!c17.sub.length) { c17.sub = null; c17.payload = Buffer.alloc(0); }
        return true;
      }
    }
  }
  return false;
}

const byName = (nm) => g.byName.get(nm);

// 经实机 1604x960 像素实测反推校准的单行文字安全盒宽：
// - 实测千星客户端 Text 组件左右各有 ~5px（共 10px）内边距
// - 实测 18px 汉字约 17.8px/字、17px 汉字约 16.7px/字；若宽度略紧且含空格会整段 word-wrap 折行裁切
// - 本函数按保守上限（汉字 1.04、标点 0.96、ASCII 0.64、空格 0.42）加 20px 内边距与防折行安全余量
function measureInkWidth(text, size) {
  let units = 0;
  for (const ch of String(text)) {
    const code = ch.codePointAt(0);
    if (ch === ' ') units += 0.42;
    else if (ch === '•' || ch === '·') units += 0.60;
    else if (code < 128) units += 0.64;
    else if ('，。；：！？（）「」【】、＝'.includes(ch)) units += 0.96;
    else units += 1.04;
  }
  return Math.ceil(units * size);
}

function safeSingleLineWidth(text, size, extraPad = 20) {
  return measureInkWidth(text, size) + extraPad;
}

function placeLeftText(name, leftX, y, w, h, props) {
  const r = byName(name);
  assert(r, '缺少文本控件: ' + name);
  setHidden(r, false);
  setRectAllStates(r, [leftX + w / 2, y], [w, h]);
  setTextProps(r, { ...props, alignH: 0 });
  stat.tutTexts++;
}

function placeBadgeIcon(prefix, key, cx, y, spriteId, iconColor = '#FFF5D6') {
  const bg = byName(`${prefix}.${key}.bg`);
  const ic = byName(`${prefix}.${key}`);
  assert(bg && ic, `缺少按钮图标控件: ${prefix}.${key}`);
  setHidden(bg, false);
  setHidden(ic, false);
  setRectAllStates(bg, [cx, y], [24, 24]);
  setRectAllStates(ic, [cx, y], [18, 18]);
  setImgProps(bg, { sprite: 100002, color: '#6C402E' });
  setImgProps(ic, { sprite: spriteId, color: iconColor });
  stat.tutIcons++;
}

function placeFlatIcon(name, cx, y, spriteId, color = '#6C402E') {
  const ic = byName(name);
  assert(ic, '缺少图标控件: ' + name);
  setHidden(ic, false);
  setRectAllStates(ic, [cx, y], [22, 22]);
  setImgProps(ic, { sprite: spriteId, color });
  stat.tutIcons++;
}

// ═════════════════════════════════════════════════════════════════════════════
// 颜色常量
// ═════════════════════════════════════════════════════════════════════════════
const C_INK        = '#231108';
const C_INK_SUB    = '#4A2816';
const C_ACCENT     = '#B82914';
const C_GREEN_TXT  = '#1D6A36';
const C_WHITE_WARM = '#FFF9E8';
// ★ 754(3)：顶部步骤条已完成绿勾专用高对比翠绿（直接配 100102 标准对勾贴图）
const C_DONE_CHECK = '#88E564';

// ═════════════════════════════════════════════════════════════════════════════
// PART A：修复全部 8 个教程页的文本防截断 + 统一撤销/按钮名文字染色
// ═════════════════════════════════════════════════════════════════════════════

// ── A1. 首页教程 td.home.page.1（三行图文混排全面放宽，彻底消除截断 + 统一撤销染色）──
{
  const p = 'td.home.page.1';

  // 卡片 1 行 2 (Y=100)：家具注释问号行
  const homeHelpPre = '• 椅/毯可站，桌/植物不可站，可点';
  const homeHelpPreW = safeSingleLineWidth(homeHelpPre, 18); // ~324
  placeLeftText(`${p}.rule.1.body.1.0`, -674, 100, homeHelpPreW, 36, {
    text: homeHelpPre,
    size: 18, minSize: 16, color: C_INK,
  });
  const homeHelpCx = -674 + homeHelpPreW + 2 + 11;
  placeFlatIcon(`${p}.help619.icon`, homeHelpCx, 100, 100113, '#6C402E');
  placeLeftText(`${p}.rule.1.body.3.0`, homeHelpCx + 11 + 4, 100, 220, 36, {
    text: '查看本关家具注释',
    size: 18, minSize: 16, color: C_INK_SUB,
  });

  // 卡片 1 行 3 (Y=68)：提交图标行
  const homeSubPre = '• 摆满后点右侧';
  const homeSubPreW = safeSingleLineWidth(homeSubPre, 18); // ~152
  placeLeftText(`${p}.rule.1.body.2.0`, -674, 68, homeSubPreW, 36, {
    text: homeSubPre,
    size: 18, minSize: 16, color: C_INK,
  });
  const homeSubCx = -674 + homeSubPreW + 2 + 12;
  placeBadgeIcon(p, 'ico.submit', homeSubCx, 68, 100110, '#FFF5D6');
  placeLeftText(`${p}.ico.submit.t`, homeSubCx + 12 + 4, 68, 460, 36, {
    text: '提交：找对盗窃者即胜，全对完美通关',
    size: 18, minSize: 16, color: C_ACCENT,
  });

  // 卡片 3 行 3 (Y=-252)：撤销 / 重做行（放宽前置与「撤销」框，且撤销与重做统一为深墨黑棕 C_INK）
  const homeUndoPre = '• 摆错了点右侧';
  const homeUndoPreW = safeSingleLineWidth(homeUndoPre, 18); // ~152
  placeLeftText(`${p}.rule.5.body.2.0`, -674, -252, homeUndoPreW, 36, {
    text: homeUndoPre,
    size: 18, minSize: 16, color: C_INK,
  });
  const homeUndoCx = -674 + homeUndoPreW + 2 + 12;
  placeBadgeIcon(p, 'ico.undo', homeUndoCx, -252, 100127, '#FFF5D6');
  const homeUndoTX = homeUndoCx + 12 + 2;
  const homeUndoTW = safeSingleLineWidth('撤销', 18); // ~58
  placeLeftText(`${p}.ico.undo.t`, homeUndoTX, -252, homeUndoTW, 36, {
    text: '撤销',
    size: 18, minSize: 16, color: C_INK,
  });
  const homeRedoCx = homeUndoTX + homeUndoTW + 4 + 12;
  placeBadgeIcon(p, 'ico.redo', homeRedoCx, -252, 100126, '#FFF5D6');
  placeLeftText(`${p}.ico.redo.t`, homeRedoCx + 12 + 2, -252, 360, 36, {
    text: '重做，卡关可点右下角提示',
    size: 18, minSize: 16, color: C_INK,
  });
}

// ── A2. 第一关教程 td.l1（4 页：page.1 / page.3 / page.7 / page.8）────────────
// L1 第 1/4 步（td.l1.page.1）
{
  const p = 'td.l1.page.1';
  setRectAllStates(byName(`${p}.tagbg`), [-550, 160], [266, 32]);
  setRectAllStates(byName(`${p}.tag`),   [-550, 160], [272, 36]);

  const l1HelpTxt = '受害者(V)也要摆进棋盘；家具注释可点关内右上角';
  const l1HelpW = safeSingleLineWidth(l1HelpTxt, 17); // ~416
  placeLeftText(`${p}.notet`, -654, -218, l1HelpW, 36, {
    text: l1HelpTxt,
    size: 17, minSize: 15, color: C_INK,
  });
  placeFlatIcon(`${p}.help619.icon`, -654 + l1HelpW + 2 + 11, -218, 100113, '#6C402E');
}

// L1 第 2/4 步（td.l1.page.3）：修复「摆错了？点右」「撤」截断 + 撤销统一为 C_INK
{
  const p = 'td.l1.page.3';
  setRectAllStates(byName(`${p}.tagbg`), [-542, 160], [282, 32]);
  setRectAllStates(byName(`${p}.tag`),   [-542, 160], [288, 36]);

  const l1p3Pre = '摆错了？点右侧';
  const l1p3PreW = safeSingleLineWidth(l1p3Pre, 17); // ~142
  placeLeftText(`${p}.notet`, -654, -218, l1p3PreW, 36, {
    text: l1p3Pre,
    size: 17, minSize: 15, color: C_INK,
  });
  const l1p3UndoCx = -654 + l1p3PreW + 2 + 12;
  placeBadgeIcon(p, 'ico.undo', l1p3UndoCx, -218, 100127, '#FFF5D6');
  const l1p3UndoTX = l1p3UndoCx + 12 + 2;
  const l1p3UndoTW = safeSingleLineWidth('撤销', 17); // ~56
  placeLeftText(`${p}.ico.undo.t`, l1p3UndoTX, -218, l1p3UndoTW, 36, {
    text: '撤销',
    size: 17, minSize: 15, color: C_INK,
  });
  const l1p3RedoCx = l1p3UndoTX + l1p3UndoTW + 4 + 12;
  placeBadgeIcon(p, 'ico.redo', l1p3RedoCx, -218, 100126, '#FFF5D6');
  placeLeftText(`${p}.ico.redo.t`, l1p3RedoCx + 12 + 2, -218, 340, 36, {
    text: '重做（也可随时重置本关）',
    size: 17, minSize: 15, color: C_INK,
  });
}

// L1 第 3/4 步（td.l1.page.7）
{
  const p = 'td.l1.page.7';
  setRectAllStates(byName(`${p}.tagbg`), [-550, 160], [266, 32]);
  setRectAllStates(byName(`${p}.tag`),   [-550, 160], [272, 36]);
}

// L1 第 4/4 步（td.l1.page.8）：修复「• 全部 5」「提」「卡住了？点右下」截断 + 提交文字统一为 C_INK
{
  const p = 'td.l1.page.8';
  setRectAllStates(byName(`${p}.tagbg`), [-550, 160], [266, 32]);
  setRectAllStates(byName(`${p}.tag`),   [-550, 160], [272, 36]);

  const l1p8SubPre = '• 全部 5 人摆上棋盘后，点右侧';
  const l1p8SubPreW = safeSingleLineWidth(l1p8SubPre, 18); // ~302
  placeLeftText(`${p}.body.0.0`, -674, 68, l1p8SubPreW, 38, {
    text: l1p8SubPre,
    size: 18, minSize: 16, color: C_INK,
  });
  const l1p8SubCx = -674 + l1p8SubPreW + 2 + 12;
  placeBadgeIcon(p, 'ico.submit', l1p8SubCx, 68, 100110, '#FFF5D6');
  const l1p8SubTX = l1p8SubCx + 12 + 2;
  const l1p8SubTW = safeSingleLineWidth('提交', 18); // ~58
  placeLeftText(`${p}.ico.submit.t`, l1p8SubTX, 68, l1p8SubTW, 38, {
    text: '提交',
    size: 18, minSize: 16, color: C_INK,
  });
  placeLeftText(`${p}.body.1.0`, l1p8SubTX + l1p8SubTW + 2, 68, 220, 38, {
    text: '再点确认即可判题',
    size: 18, minSize: 16, color: C_INK,
  });

  const l1p8HintPre = '卡住了？点右下角';
  const l1p8HintPreW = safeSingleLineWidth(l1p8HintPre, 17); // ~160
  placeLeftText(`${p}.notet`, -654, -218, l1p8HintPreW, 36, {
    text: l1p8HintPre,
    size: 17, minSize: 15, color: C_INK,
  });
  const l1p8HintCx = -654 + l1p8HintPreW + 2 + 12;
  placeBadgeIcon(p, 'ico.hint', l1p8HintCx, -218, 100120, '#FFF5D6');
  placeLeftText(`${p}.ico.hint.t`, l1p8HintCx + 12 + 2, -218, 400, 36, {
    text: '提示：揭示位置 1 次 / 验真假 2 次',
    size: 17, minSize: 15, color: C_INK,
  });

  // 顺手放宽棋盘下方说明，避免过紧
  setRectAllStates(byName(`${p}.caption`), [275.0, -240.0], [520, 36]);
}

// ── A3. 第二关教程 td.l2（3 页：page.2 / page.3 / page.4）────────────────────
// L2 第 1/3 步（td.l2.page.2）
{
  const p = 'td.l2.page.2';
  setRectAllStates(byName(`${p}.tagbg`), [-558, 160], [250, 32]);
  setRectAllStates(byName(`${p}.tag`),   [-558, 160], [256, 36]);
}

// L2 第 2/3 步（td.l2.page.3）：放宽底栏「拿不准真假？选中线索后点右下角」与右侧速览宽度
{
  const p = 'td.l2.page.3';
  setRectAllStates(byName(`${p}.tagbg`), [-558, 160], [250, 32]);
  setRectAllStates(byName(`${p}.tag`),   [-558, 160], [256, 36]);

  const l2p3Pre = '拿不准真假？选中线索后点右下角';
  const l2p3PreW = safeSingleLineWidth(l2p3Pre, 17); // ~284
  placeLeftText(`${p}.notet`, -654, -94, l2p3PreW, 36, {
    text: l2p3Pre,
    size: 17, minSize: 15, color: C_INK,
  });
  const l2p3Cx = -654 + l2p3PreW + 2 + 11;
  placeFlatIcon(`${p}.ico.hint631`, l2p3Cx, -94, 100120, '#6C402E');
  placeLeftText(`${p}.note631.tail`, l2p3Cx + 11 + 4, -94, 320, 36, {
    text: '提示验证真假（每关 2 次）',
    size: 17, minSize: 15, color: C_INK,
  });

  // 速览宽由 232 → 242，保证 lgt.1（• C(椅子) 与 E(植物旁)）宽松不挤
  const SUMMARY_LEFT = 492;
  const SUMMARY_W = 242;
  setRectAllStates(byName(`${p}.legendtitle`), [SUMMARY_LEFT + SUMMARY_W / 2, 164], [SUMMARY_W, 40]);
  const ys = [120, 84, 48, -4, -40, -78];
  for (let i = 0; i < ys.length; i++) {
    setRectAllStates(byName(`${p}.lgt.${i}`), [SUMMARY_LEFT + SUMMARY_W / 2, ys[i]], [SUMMARY_W, 38]);
  }
}

// L2 第 3/3 步（td.l2.page.4）：修复「• 摆齐全部 6」与 cluesay.0「→ 实际 E」两处截断
{
  const p = 'td.l2.page.4';
  setRectAllStates(byName(`${p}.tagbg`), [-558, 160], [250, 32]);
  setRectAllStates(byName(`${p}.tag`),   [-558, 160], [256, 36]);

  const l2p4Pre = '• 摆齐全部 6 人即可破案，点击右侧';
  const l2p4PreW = safeSingleLineWidth(l2p4Pre, 18); // ~340
  placeLeftText(`${p}.rewrite617.0`, -674, -28, l2p4PreW, 36, {
    text: l2p4Pre,
    size: 18, minSize: 16, color: C_INK,
  });
  placeBadgeIcon(p, 'ico.submit', -674 + l2p4PreW + 2 + 12, -28, 100110, '#FFF5D6');

  // 放宽 cluesay.0（原 749 仅 336px，18px 下放不下整句），左缘与 cluename (-629) 基本对齐至 -614，宽 600（右缘 -14 < 15）
  placeLeftText(`${p}.cluesay.0`, -629, -240, 620, 36, {
    text: '「E 顾客在 A 服务员的上方」→ 实际 E 在第 6 行，为假',
    size: 18, minSize: 16, color: C_INK,
  });
}

// ═════════════════════════════════════════════════════════════════════════════
// PART B：修复顶部步骤条已完成步「绿勾出头太少不明显」
// 用官方标准粗体对勾贴图 100102（22x22，高对比翠绿 #88E564）替代细小变形的 Unicode ✓ 字符
// ═════════════════════════════════════════════════════════════════════════════
const DONE_STEPS = [
  ['td.l1.page.3', [1]],
  ['td.l1.page.7', [1, 2]],
  ['td.l1.page.8', [1, 2, 3]],
  ['td.l2.page.3', [1]],
  ['td.l2.page.4', [1, 2]],
];

for (const [pageName, indices] of DONE_STEPS) {
  for (const i of indices) {
    const nbg = byName(`${pageName}.stepn.${i}.bg`);
    const num = byName(`${pageName}.stepn.${i}`);
    assert(nbg && num, `缺少步骤条绿勾控件: ${pageName}.stepn.${i}`);
    const rc = getRect(nbg);
    // 直接使用清晰醒目的 100102 粗体对勾图标（22x22），高对比翠绿直接立在深棕底条上，左右勾角清晰对称
    setHidden(nbg, false);
    setRectAllStates(nbg, [rc.x, rc.y], [22, 22]);
    setImgProps(nbg, { sprite: 100102, color: C_DONE_CHECK });
    // 隐藏原本的 ✓ 文本控件避免重影
    setTextProps(num, { text: '' });
    setHidden(num, true);
    stat.tutCheckmarks++;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PART C：几何防重叠门禁 + 全局 8 页单行文本宽度防截断门禁
// ═════════════════════════════════════════════════════════════════════════════
function assertRowNoOverlap(label, names) {
  let prevRight = -Infinity;
  let refY = null;
  for (const nm of names) {
    const r = byName(nm);
    assert(r, `布局校验找不到控件: ${nm}`);
    const rc = getRect(r);
    const left = rc.x - rc.w / 2;
    const right = rc.x + rc.w / 2;
    if (refY === null) refY = rc.y;
    assert(Math.abs(rc.y - refY) < 0.01, `布局垂直不齐 [${label}]：${nm} y=${rc.y} != ${refY}`);
    assert(left >= prevRight - 0.5, `布局重叠 [${label}]：${nm} left=${left.toFixed(1)} < prevRight=${prevRight.toFixed(1)}`);
    assert(right <= 15.0, `布局越出主卡右缘 [${label}]：${nm} right=${right.toFixed(1)}`);
    prevRight = right;
  }
}

assertRowNoOverlap('home.row.help',   ['td.home.page.1.rule.1.body.1.0', 'td.home.page.1.help619.icon', 'td.home.page.1.rule.1.body.3.0']);
assertRowNoOverlap('home.row.submit', ['td.home.page.1.rule.1.body.2.0', 'td.home.page.1.ico.submit.bg', 'td.home.page.1.ico.submit.t']);
assertRowNoOverlap('home.row.undo',   ['td.home.page.1.rule.5.body.2.0', 'td.home.page.1.ico.undo.bg', 'td.home.page.1.ico.undo.t', 'td.home.page.1.ico.redo.bg', 'td.home.page.1.ico.redo.t']);
assertRowNoOverlap('l1p1.note.help',  ['td.l1.page.1.notet', 'td.l1.page.1.help619.icon']);
assertRowNoOverlap('l1p3.note.undo',  ['td.l1.page.3.notet', 'td.l1.page.3.ico.undo.bg', 'td.l1.page.3.ico.undo.t', 'td.l1.page.3.ico.redo.bg', 'td.l1.page.3.ico.redo.t']);
assertRowNoOverlap('l1p8.row.submit', ['td.l1.page.8.body.0.0', 'td.l1.page.8.ico.submit.bg', 'td.l1.page.8.ico.submit.t', 'td.l1.page.8.body.1.0']);
assertRowNoOverlap('l1p8.note.hint',  ['td.l1.page.8.notet', 'td.l1.page.8.ico.hint.bg', 'td.l1.page.8.ico.hint.t']);
assertRowNoOverlap('l2p3.note.hint',  ['td.l2.page.3.notet', 'td.l2.page.3.ico.hint631', 'td.l2.page.3.note631.tail']);
assertRowNoOverlap('l2p4.row.submit', ['td.l2.page.4.rewrite617.0', 'td.l2.page.4.ico.submit.bg']);

// 校验本关速览左对齐
{
  const lt = getRect(byName('td.l2.page.3.legendtitle'));
  const ltLeft = lt.x - lt.w / 2;
  for (let i = 0; i < 6; i++) {
    const r = getRect(byName(`td.l2.page.3.lgt.${i}`));
    const left = r.x - r.w / 2;
    assert(Math.abs(left - ltLeft) < 0.01, `td.l2.page.3.lgt.${i} 左缘(${left})未与标题(${ltLeft})对齐`);
  }
}

// ★ 全局 8 个教程页单行文本防截断门禁：逐一检查所有可见文本控件，绝不漏掉首页或任意子页
const ACTIVE_PAGES = [
  'td.home.page.1',
  'td.l1.page.1', 'td.l1.page.3', 'td.l1.page.7', 'td.l1.page.8',
  'td.l2.page.2', 'td.l2.page.3', 'td.l2.page.4',
];
const tightFailures = [];
for (const page of ACTIVE_PAGES) {
  for (const r of g.recs) {
    const nm = r.name || '';
    if (!nm.startsWith(page + '.')) continue;
    if (isHidden(r)) continue;
    const ti = getTextInfo(r);
    if (!ti || !ti.text.trim()) continue;
    // 跳过棋盘上的多格/微缩文字（如 svg.69 "盗窃者" 10px 居中）与换行的正文块
    if (nm.includes('.svg.') || nm.includes('.demo637.') || nm.includes('.hold75.') || nm.includes('.lg.')) continue;
    const rc = getRect(r);
    const minNeeded = measureInkWidth(ti.text, ti.size) + 14; // 10px 内边距 + 4px 最低安全余量
    stat.checkedTexts++;
    if (rc.w < minNeeded) {
      tightFailures.push(`${nm}: w=${rc.w.toFixed(1)} < minNeeded=${minNeeded} (fs=${ti.size}, txt=${JSON.stringify(ti.text)})`);
    }
  }
}
assert.equal(tightFailures.length, 0, '检测到过紧/可能截断的教程文本:\n' + tightFailures.join('\n'));

// 校验「撤销」与「重做」染色一致（均为 C_INK）
const inkU32 = Number(ARGB(C_INK));
for (const nm of [
  'td.home.page.1.ico.undo.t',
  'td.home.page.1.ico.redo.t',
  'td.l1.page.3.ico.undo.t',
  'td.l1.page.3.ico.redo.t',
  'td.l1.page.8.ico.submit.t',
]) {
  const ti = getTextInfo(byName(nm));
  assert.equal(ti.color, inkU32, `${nm} 颜色未统一为 C_INK`);
}

console.log('GIL_UI_PATCH_STATS_754:', JSON.stringify(stat));

// ═════════════════════════════════════════════════════════════════════════════
// PART D：内嵌 Lua 脚本仅更新构建标记（保留 753 全部经验证逻辑）
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

replaceOnce(
  'build_marker_1',
  'if print then print("[murdoku] ===== 构建标记 v753 / 教程细节与已通重提修复 =====") end',
  'if print then print("[murdoku] ===== 构建标记 v754 / 教程文本防截断与视觉精修 =====") end'
);
replaceOnce(
  'build_marker_2',
  'print("[murdoku] ===== 构建标记 v753 / 教程细节与已通重提修复 =====")',
  'print("[murdoku] ===== 构建标记 v754 / 教程文本防截断与视觉精修 =====")'
);

// ═════════════════════════════════════════════════════════════════════════════
// PART E：语法检查、隐式全局零新增、writeGil 完整往返核验与全量仿真测试
// ═════════════════════════════════════════════════════════════════════════════
const baseLuaTmp = path.join(runTmp, 'base753.lua');
const candLuaTmp = path.join(runTmp, 'cand754.lua');
fs.writeFileSync(baseLuaTmp, original, 'utf8');
fs.writeFileSync(candLuaTmp, lua, 'utf8');

function luacGlobals(filePath) {
  const r = spawnSync('luac', ['-p', '-l', filePath], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  assert.equal(r.status, 0, `luac 语法检查失败 (${filePath}):\n${r.stderr}`);
  const gets = new Set();
  const sets = new Set();
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

// 写回脚本并通过 writeGil 走完整往返重编码 + 落盘回读验证
leaf.field.payload = Buffer.from(lua, 'utf8');
const stageGil = path.join(runTmp, '754_stage.gil');
const writeReport = writeGil(g, stageGil, {
  label: '754 教程文本防截断与视觉精修',
  assert: (gBack) => {
    assert.equal(gBack.recs.length, g.recs.length, '控件记录数意外变化');
    assert.equal(findScriptLeaf(gBack).buf.toString('utf8'), lua, '回读内嵌脚本不一致');

    // 1) 验证单人配置 Top#11 原样保留（与 753.gil 一致）
    const gBaseCheck = loadTree(base);
    const t11Base = gBaseCheck.tree.find((x) => x.field === 11);
    const t11Out  = gBack.tree.find((x) => x.field === 11);
    const f11_6_base = t11Base.sub.find((x) => x.field === 6).sub[0].sub.find((x) => x.field === 502);
    const f11_6_out  = t11Out.sub.find((x) => x.field === 6).sub[0].sub.find((x) => x.field === 502);
    assert.equal(f11_6_out.num, 1n, 'Top#11 单人分组人数上限不是 1');
    assert.equal(f11_6_out.num, f11_6_base.num, 'Top#11 单人分组配置被意外修改');
    const f11_2_out = t11Out.sub.find((x) => x.field === 2).sub[0].sub.find((x) => x.field === 4);
    assert.equal(f11_2_out.payload.length, 1, 'Top#11 初始玩家阵营人数不是 1');

    // 2) 回读验证全部 9 处已完成步绿勾已换为 100102 贴图且旧 ✓ 文本隐藏
    for (const [pageName, indices] of DONE_STEPS) {
      for (const i of indices) {
        const bgRec = gBack.byName.get(`${pageName}.stepn.${i}.bg`);
        const numRec = gBack.byName.get(`${pageName}.stepn.${i}`);
        const c84 = getImgComp(bgRec);
        const sp = c84.sub.find((y) => y.field === 503 && y.wt === 0);
        const col = c84.sub.find((y) => y.field === 502 && y.wt === 0);
        assert.equal(sp.num, 100102n, `回读 ${pageName}.stepn.${i}.bg 贴图不是 100102`);
        assert.equal(col.num, ARGB(C_DONE_CHECK), `回读 ${pageName}.stepn.${i}.bg 颜色不是 ${C_DONE_CHECK}`);
        assert.equal(isHidden(numRec), true, `回读 ${pageName}.stepn.${i} 字符未隐藏`);
      }
    }

    // 3) 回读验证截断重灾区宽度与撤销染色
    const cSay = getRect(gBack.byName.get('td.l2.page.4.cluesay.0'));
    assert(cSay.w >= 600, `回读 td.l2.page.4.cluesay.0 宽度不足: ${cSay.w}`);
    for (const nm of ['td.home.page.1.ico.undo.t', 'td.l1.page.3.ico.undo.t', 'td.l1.page.8.ico.submit.t']) {
      assert.equal(getTextInfo(gBack.byName.get(nm)).color, inkU32, `回读 ${nm} 颜色不是 C_INK`);
    }
    return true;
  },
});

// 导出控件树并执行全套离线高仿真 Lua 回归测试
const treePath = path.join(runTmp, 'tree754.lua');
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
const animJsonPath = path.join(runTmp, 'verify_749_on_754.json');
{
  const r = spawnSync('lua', [path.join(repo, 'tests/verify_749_paper_anim.lua'), treePath, candLuaTmp, animJsonPath], { encoding: 'utf8', cwd: repo });
  assert.equal(r.status, 0, 'verify_749_paper_anim 失败:\n' + r.stdout + '\n' + r.stderr);
  process.stdout.write(r.stdout);
  assert(r.stdout.includes('VERIFY_749_PASS=true'), 'verify_749_paper_anim 未通过');
}

// 3) 754 专项回归测试（A..J 共 10 项）
const feedbackJson = path.join(runTmp, 'verify_754_feedback.json');
{
  const r = spawnSync('lua', [path.join(repo, 'tests/verify_754_feedback.lua'), treePath, candLuaTmp, feedbackJson], { encoding: 'utf8', cwd: repo });
  process.stdout.write(r.stdout);
  assert.equal(r.status, 0, 'verify_754_feedback 失败:\n' + r.stderr + r.stdout);
  assert(r.stdout.includes('VERIFY_754_PASS=true'), 'verify_754_feedback 未通过');
}

// 全部门禁通过后正式落盘 754 新目录（绝不覆盖 750/751/752/753 旧档）
const outDir = path.dirname(out);
fs.mkdirSync(outDir, { recursive: true });
fs.copyFileSync(stageGil, out);
const diskBuf = fs.readFileSync(out);
fs.writeFileSync(path.join(outDir, '754_内嵌脚本.lua'), lua, 'utf8');

const report = {
  version: '754',
  base: path.relative(repo, base),
  base_sha256: sha(g.src),
  output: path.relative(repo, out),
  output_bytes: diskBuf.length,
  output_sha256: sha(diskBuf),
  records_count: g.recs.length,
  field_diffs: writeReport.diffs,
  single_player_preserved: { faction_players: 1, group_max_players: 1 },
  globals_gate: { newGets: 0, newSets: 0 },
  ui_patch_stats: stat,
  verify749PaperAnim: JSON.parse(fs.readFileSync(animJsonPath, 'utf8')),
  feedback_tests: JSON.parse(fs.readFileSync(feedbackJson, 'utf8')),
};
fs.writeFileSync(path.join(outDir, '754_验证与结构报告.json'), JSON.stringify(report, null, 2), 'utf8');

if (!keepTmp) fs.rmSync(runTmp, { recursive: true, force: true });
console.log('BUILD_754_OK:', out, 'bytes=' + diskBuf.length, 'sha256=' + report.output_sha256);
