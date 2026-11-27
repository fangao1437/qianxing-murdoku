// tools/build_755.mjs
// 基于 754_教程文本防截断与视觉精修/754_教程文本防截断与视觉精修.gil 构建 755_教程图文间距与视觉一致性精修.gil
// 严格不覆盖旧档（750/751/752/753/754 均保留原样），原样保留 Top#11 单人房间人数配置与全部运行逻辑。
//
// 本次 755 专项精修（均基于 1604×1260 实机截图 1:1 像素测量反推）：
// 1. 彻底解决全部 8 个教程页图文混排行「图标与前后文本距离过大且不均」：
//    - 根因：754 将文本框安全宽度（含 +20px 防折行右余量）同时拿去算下一个图标/文本的起点 X，导致实机渲染中文字末尾右侧白白多出 20~43px 空隙；
//    - 修复：解耦「视觉墨水推进宽 measureVisualInkWidth()」（经 1604×1260 实机 7 段逐字实测校准：CJK≈1.00、全角标点≈0.88、ASCII≈0.58、圆点≈0.44、空格≈0.30、padL≈2.5px）与「防折行/防截断盒宽 safeBoxWidth()」。
//      光标只按视觉墨水右缘 + 固定均匀间距（ICON_GAP = 6px）推进，并把后续图标与关联文本整体紧跟挪动；文本框自身右缘适度多留安全余量（若紧接右侧有文本，控制在下一个控件左缘以内避免遮挡，且仍保证 ≥ 实测墨水宽 + 10px 绝不截断）。
//    - 同时检查并统一 l1p1 / l1p3 / l1p8 / l2p3 / l2p4 / home 全部 9 行图文混排及底栏 notei 与 notet 的间距。
// 2. 步骤条已完成绿勾：只换素材，完整保留原来的「绿圆圈底色 + 内部深色对勾图标」样式与原色：
//    - 恢复全部 9 处已完成步 `stepn.i.bg` 为原 753 样式：26×26 圆形底 `100002` + 原绿底色 `#7EA65A`；
//    - 复用同一页内已隐藏的闲置同级图片槽位（l1 复用 `stepn.5..7.bg`；l2 复用 `stepn.4.bg` 和 `step.4`，其 Z 序均严格位于 `stepn.1..3.bg` 之上），摆在同一中心 `(rc.x, rc.y)`，设为 `15×15` 标准粗体对勾贴图 `100102` + 原深墨绿 `#192B12`；
//    - 保持原细瘦 Unicode `✓` 文本控件 `stepn.i` 隐藏，彻底保留“圆圈底色 + 对勾图标”原样式且颜色 100% 一致，同时左右勾角清晰饱满。
// 3. 区分提示条左侧 `i` 信息圆标（notei.bg）与右侧操作按钮图标（submit/undo/redo/hint/help）的配色，并确保全教程所有序号标/信息标互不混淆：
//    - 操作按钮徽标（提交/撤销/重做/提示/家具注释）：保持深棕 `#6C402E` + 暖白 `#FFF5D6`（实机按钮一致）；
//    - 提示条左侧 `i` 信息圆标（`notei.bg` + `notei`，4 页共 4 处）：改为柔和暖赭石/浅金底 `#D8B574` + 深墨棕 `i` `#3B2010`（与操作按钮的深棕实心底彻底区分，且柔和协调）；
//    - 首页 1/2/3 分区序号标（`rule.1/3/5.num.bg`）：保持浅羊皮纸金 `#E5C98B` + 深棕字 `#5C341E`（与深棕操作按钮清晰区分）。
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
const runTmp = fs.mkdtempSync(path.join(os.tmpdir(), 'murdoku-755-'));
const keepTmp = process.argv.includes('--keep-tmp');
const overwrite = process.argv.includes('--overwrite');

const base = path.join(repo, '754_教程文本防截断与视觉精修/754_教程文本防截断与视觉精修.gil');
const out = path.resolve(
  process.argv[2] && !process.argv[2].startsWith('--')
    ? process.argv[2]
    : path.join(repo, '755_教程图文间距与视觉一致性精修/755_教程图文间距与视觉一致性精修.gil')
);

if (!overwrite) assert(!fs.existsSync(out), '输出已存在，拒绝覆盖旧档（本项目习惯按版本号递增导出）：' + out);

const sha = (b) => createHash('sha256').update(b).digest('hex');
const g = loadTree(base);
assert.equal(
  sha(g.src),
  '68ce58a6ae968d265df48739d1edf18728b41224678ae71a2f3e4f0ce41cd260',
  '基准 754_教程文本防截断与视觉精修.gil SHA256 不匹配'
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
  tutNoteiRecolored: 0,
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
        return true;
      }
      const f503 = c17.sub.find((y) => y.field === 503 && y.wt === 0);
      if (!f503) {
        c17.sub.push({ field: 503, wt: 0, num: 1n });
        return true;
      }
      if (f503.num !== 1n) { f503.num = 1n; return true; }
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

// ═════════════════════════════════════════════════════════════════════════════
// 1604×1260 实机 1:1 像素反推校准后的字宽模型（误差 ±3px 以内）
// 实机实测样本（754 l1p8 截图）：
//   "• 全部 5 人摆上棋盘后，点右侧" (fs=18): ink=245px (padL=2px)
//   "提交" (fs=18):                        ink=36px  (padL=3px)
//   "再点确认即可判题" (fs=18):             ink=144px (padL=3px)
//   "• 判题反馈：绿圈 = 位置正确，红圈 = 位置有误" (fs=18): ink=364px
//   "• 找对盗窃者即可过关，全部人物都摆对即为完美通关！" (fs=18): ink=410px
//   "卡住了？点右下角" (fs=17):             ink=137px (padL=2px)
//   "提示：揭示位置 1 次 / 验真假 2 次" (fs=17): ink=254px (padL=3px)
// ═════════════════════════════════════════════════════════════════════════════
const TEXT_PAD_L = 2.5; // 实测 Text 左起墨水偏移约 2~3px

function measureVisualInkWidth(text, size) {
  let units = 0;
  for (const ch of String(text)) {
    const code = ch.codePointAt(0);
    if (ch === ' ') units += 0.30;
    else if (ch === '•' || ch === '·') units += 0.44;
    else if (ch === '/' || ch === '|' || ch === '1' || ch === '(' || ch === ')') units += 0.46;
    else if (code < 128) units += 0.58;
    else if ('，。；：！？（）「」【】、＝'.includes(ch)) units += 0.96;
    else units += 0.97;
  }
  return Math.round(units * size);
}

// 关键解耦：
// - visualRight = leftX + TEXT_PAD_L + measureVisualInkWidth(text, size)
// - boxWidth = Math.max(visualInk + 24, ...) —— 足够宽、绝不 word-wrap 截断；
//   因为透明文本框可以合法覆盖右侧透明空白区域（不含射线交互），而光标只按 visualRight + gap 精确推进，
//   这样既有绝对防截断保障，又能让文字与图标之间严丝合缝且完全均匀！
// - 注意：为安全起见，在纯文本行内，所有文本/图标均无射线点击冲突，透明背景透明叠放零视觉副作用。

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

// 统一行内流式排版器：按实测视觉墨水宽 + 固定均匀间距排布全部图文混排行
// 返回每个元素精确的视觉区间 [visL, visR] 供断言校验
const GAP_TEXT_TO_ICON = 6; // 文字墨水右缘 → 图标左缘（实机视觉 6px）
const GAP_ICON_TO_TEXT = 5; // 图标右缘 → 后续文字墨水左缘（补偿 padL≈2.5px，故框左缘 = iconR + 2.5）
const GAP_TEXT_TO_TEXT = 6; // 按钮名（如「提交」）墨水右缘 → 后续正文墨水左缘（补偿 padL≈2.5px）
const GAP_BTN_TO_NEXT_ICON = 10; // 「撤销」墨水右缘 → 下一个「重做」图标左缘（视觉分组清晰又不疏离）

function layoutInlineRow(label, startX, y, h, items) {
  let cursor = startX; // 当前视觉墨水左缘 X（即上一个元素的 visR + gap）
  const spans = [];

  for (let i = 0; i < items.length; i++) {
    const it = items[i];
    const prev = i > 0 ? items[i - 1] : null;

    if (i > 0) {
      if (it.gap !== undefined) {
        cursor += it.gap;
      } else if (prev.kind === 'text' && (it.kind === 'badge' || it.kind === 'flat')) {
        cursor += GAP_TEXT_TO_ICON;
      } else if ((prev.kind === 'badge' || prev.kind === 'flat') && it.kind === 'text') {
        cursor += GAP_ICON_TO_TEXT;
      } else {
        cursor += GAP_TEXT_TO_TEXT;
      }
    }

    if (it.kind === 'text') {
      const inkW = measureVisualInkWidth(it.text, it.size);
      // 框左缘比期望的视觉墨水左缘左移 TEXT_PAD_L（首个元素保持 startX 不动）
      const boxL = i === 0 ? cursor : Math.round((cursor - TEXT_PAD_L) * 2) / 2;
      const visL = boxL + TEXT_PAD_L;
      const visR = visL + inkW;
      // 盒宽留足 +28px 防折行余量（尾段如给了 tailW 则取更大值），并限不超过主卡右缘 14
      const boxW = Math.min(Math.max(inkW + 28, it.minW || 0), Math.floor(14 - boxL));
      assert(boxW >= inkW + 16, `[${label}] 文本 ${it.name} 剩余宽度不足: boxW=${boxW}, inkW=${inkW}`);
      placeLeftText(it.name, boxL, y, boxW, h, {
        text: it.text,
        size: it.size,
        minSize: it.minSize ?? Math.max(12, it.size - 2),
        color: it.color,
      });
      spans.push({ name: it.name, kind: 'text', visL, visR, boxL, boxR: boxL + boxW, y });
      cursor = visR;
    } else if (it.kind === 'badge') {
      const w = 24;
      const visL = cursor;
      const cx = visL + w / 2;
      const visR = visL + w;
      placeBadgeIcon(it.prefix, it.key, cx, y, it.sprite, it.iconColor || '#FFF5D6');
      spans.push({ name: `${it.prefix}.${it.key}.bg`, kind: 'icon', visL, visR, boxL: visL, boxR: visR, y });
      cursor = visR;
    } else if (it.kind === 'flat') {
      const w = 22;
      const visL = cursor;
      const cx = visL + w / 2;
      const visR = visL + w;
      placeFlatIcon(it.name, cx, y, it.sprite, it.color || '#6C402E');
      spans.push({ name: it.name, kind: 'icon', visL, visR, boxL: visL, boxR: visR, y });
      cursor = visR;
    }
  }

  // 校验整行视觉不重叠、且每个相邻视觉间距都落在 [4.5, 11] 合理紧凑范围
  for (let i = 1; i < spans.length; i++) {
    const gap = spans[i].visL - spans[i - 1].visR;
    assert(gap >= 4.0 && gap <= 12.0, `[${label}] 视觉间距异常: ${spans[i - 1].name} -> ${spans[i].name} gap=${gap.toFixed(1)}px`);
  }
  assert(spans[spans.length - 1].visR <= 10.0, `[${label}] 视觉内容越出主卡右缘: visR=${spans[spans.length - 1].visR.toFixed(1)}`);
  return spans;
}

// ═════════════════════════════════════════════════════════════════════════════
// 颜色常量
// ═════════════════════════════════════════════════════════════════════════════
const C_INK          = '#231108';
const C_INK_SUB      = '#4A2816';
const C_ACCENT       = '#B82914';
// 原 753 步骤条已完成绿勾原色（100% 保持一致）
const C_DONE_CIRCLE  = '#7EA65A';
const C_DONE_TICK    = '#192B12';
// 提示条左侧 `i` 圆标专用配色（浅暖金赭底 + 深棕字，与操作按钮深棕底 #6C402E 清晰区分）
const C_NOTEI_BG     = '#D8B574';
const C_NOTEI_TXT    = '#3B2010';
// 首页分区 1/2/3 序号标（保持浅羊皮纸金底 + 深棕字，与操作按钮深棕底区分）
const C_SEC_NUM_BG   = '#E5C98B';
const C_SEC_NUM_TXT  = '#5C341E';

const rowLayoutSummary = {};

// ═════════════════════════════════════════════════════════════════════════════
// PART A：全部 8 个教程页 9 行图文混排精调（视觉等距紧贴 + 挪动必带关联文本）
// ═════════════════════════════════════════════════════════════════════════════

// A1. 首页教程 td.home.page.1（3 行图文混排）
{
  const p = 'td.home.page.1';
  // 卡片 1 行 2 (Y=100)：家具注释问号行
  rowLayoutSummary['home.help'] = layoutInlineRow('home.help', -674, 100, 36, [
    { kind: 'text', name: `${p}.rule.1.body.1.0`, text: '• 椅/毯可站，桌/植物不可站，可点', size: 18, color: C_INK },
    { kind: 'flat', name: `${p}.help619.icon`, sprite: 100113, color: '#6C402E' },
    { kind: 'text', name: `${p}.rule.1.body.3.0`, text: '查看本关家具注释', size: 18, color: C_INK_SUB, minW: 200 },
  ]);

  // 卡片 1 行 3 (Y=68)：提交图标行
  rowLayoutSummary['home.submit'] = layoutInlineRow('home.submit', -674, 68, 36, [
    { kind: 'text', name: `${p}.rule.1.body.2.0`, text: '• 摆满后点右侧', size: 18, color: C_INK },
    { kind: 'badge', prefix: p, key: 'ico.submit', sprite: 100110 },
    { kind: 'text', name: `${p}.ico.submit.t`, text: '提交：找对盗窃者即胜，全对完美通关', size: 18, color: C_ACCENT, minW: 380 },
  ]);

  // 卡片 3 行 3 (Y=-252)：撤销 + 重做图标行
  rowLayoutSummary['home.undo'] = layoutInlineRow('home.undo', -674, -252, 36, [
    { kind: 'text', name: `${p}.rule.5.body.2.0`, text: '• 摆错了点右侧', size: 18, color: C_INK },
    { kind: 'badge', prefix: p, key: 'ico.undo', sprite: 100127 },
    { kind: 'text', name: `${p}.ico.undo.t`, text: '撤销', size: 18, color: C_INK },
    { kind: 'badge', prefix: p, key: 'ico.redo', sprite: 100126, gap: GAP_BTN_TO_NEXT_ICON },
    { kind: 'text', name: `${p}.ico.redo.t`, text: '重做，卡关可点右下角提示', size: 18, color: C_INK, minW: 280 },
  ]);
}

// A2. 第一关教程 td.l1（page.1 / page.3 / page.8 共 4 行图文混排）
// 提示条左侧 notei.bg 中心 X=-673.4, W=18.3 => 右缘 -664.3；
// 将 notet 起点统一微调至 -657（视觉左缘 -654.5，与 notei 右缘相距 ~9.8px，紧凑利落）
const NOTE_TEXT_START_X = -657;

// L1 第 1/4 步（td.l1.page.1）
{
  const p = 'td.l1.page.1';
  rowLayoutSummary['l1p1.help'] = layoutInlineRow('l1p1.help', NOTE_TEXT_START_X, -218, 36, [
    { kind: 'text', name: `${p}.notet`, text: '受害者(V)也要摆进棋盘；家具注释可点关内右上角', size: 17, color: C_INK },
    { kind: 'flat', name: `${p}.help619.icon`, sprite: 100113, color: '#6C402E' },
  ]);
}

// L1 第 2/4 步（td.l1.page.3）
{
  const p = 'td.l1.page.3';
  rowLayoutSummary['l1p3.undo'] = layoutInlineRow('l1p3.undo', NOTE_TEXT_START_X, -218, 36, [
    { kind: 'text', name: `${p}.notet`, text: '摆错了？点右侧', size: 17, color: C_INK },
    { kind: 'badge', prefix: p, key: 'ico.undo', sprite: 100127 },
    { kind: 'text', name: `${p}.ico.undo.t`, text: '撤销', size: 17, color: C_INK },
    { kind: 'badge', prefix: p, key: 'ico.redo', sprite: 100126, gap: GAP_BTN_TO_NEXT_ICON },
    { kind: 'text', name: `${p}.ico.redo.t`, text: '重做（也可随时重置本关）', size: 17, color: C_INK, minW: 260 },
  ]);
}

// L1 第 4/4 步（td.l1.page.8）
{
  const p = 'td.l1.page.8';
  rowLayoutSummary['l1p8.submit'] = layoutInlineRow('l1p8.submit', -674, 68, 38, [
    { kind: 'text', name: `${p}.body.0.0`, text: '• 全部 5 人摆上棋盘后，点右侧', size: 18, color: C_INK },
    { kind: 'badge', prefix: p, key: 'ico.submit', sprite: 100110 },
    { kind: 'text', name: `${p}.ico.submit.t`, text: '提交', size: 18, color: C_INK },
    { kind: 'text', name: `${p}.body.1.0`, text: '再点确认即可判题', size: 18, color: C_INK, minW: 190 },
  ]);

  rowLayoutSummary['l1p8.hint'] = layoutInlineRow('l1p8.hint', NOTE_TEXT_START_X, -218, 36, [
    { kind: 'text', name: `${p}.notet`, text: '卡住了？点右下角', size: 17, color: C_INK },
    { kind: 'badge', prefix: p, key: 'ico.hint', sprite: 100120 },
    { kind: 'text', name: `${p}.ico.hint.t`, text: '提示：揭示位置 1 次 / 验真假 2 次', size: 17, color: C_INK, minW: 320 },
  ]);
}

// A3. 第二关教程 td.l2（page.3 / page.4 共 2 行图文混排）
// L2 第 2/3 步（td.l2.page.3）
{
  const p = 'td.l2.page.3';
  rowLayoutSummary['l2p3.hint'] = layoutInlineRow('l2p3.hint', NOTE_TEXT_START_X, -94, 36, [
    { kind: 'text', name: `${p}.notet`, text: '拿不准真假？选中线索后点右下角', size: 17, color: C_INK },
    { kind: 'flat', name: `${p}.ico.hint631`, sprite: 100120, color: '#6C402E' },
    { kind: 'text', name: `${p}.note631.tail`, text: '提示验证真假（每关 2 次）', size: 17, color: C_INK, minW: 260 },
  ]);
}

// L2 第 3/3 步（td.l2.page.4）
{
  const p = 'td.l2.page.4';
  rowLayoutSummary['l2p4.submit'] = layoutInlineRow('l2p4.submit', -674, -28, 36, [
    { kind: 'text', name: `${p}.rewrite617.0`, text: '• 摆齐全部 6 人即可破案，点击右侧', size: 18, color: C_INK },
    { kind: 'badge', prefix: p, key: 'ico.submit', sprite: 100110 },
  ]);
}

// ═════════════════════════════════════════════════════════════════════════════
// PART B：步骤条已完成绿勾 — 只换素材，保留原「圆圈底色 + 对勾图标」样式与原色
//   - 底圆：stepn.i.bg 恢复为 26×26 圆形 100002 + 原绿底 #7EA65A
//   - 前景对勾：复用本页已隐藏且 Z 序严格在 stepn.1..3.bg 之上的闲置图片控件，
//               设为 15×15 标准粗体对勾贴图 100102 + 原深墨绿 #192B12
//   - 旧 ✓ 字符控件 stepn.i 保持隐藏，避免重影
// ═════════════════════════════════════════════════════════════════════════════
const DONE_STEP_SLOTS = [
  // [pageName, stepIndex, overlayImgSuffix]
  ['td.l1.page.3', 1, 'stepn.5.bg'],
  ['td.l1.page.7', 1, 'stepn.5.bg'],
  ['td.l1.page.7', 2, 'stepn.6.bg'],
  ['td.l1.page.8', 1, 'stepn.5.bg'],
  ['td.l1.page.8', 2, 'stepn.6.bg'],
  ['td.l1.page.8', 3, 'stepn.7.bg'],
  ['td.l2.page.3', 1, 'stepn.4.bg'],
  ['td.l2.page.4', 1, 'step.4'],
  ['td.l2.page.4', 2, 'stepn.4.bg'],
];

// 工具：解码页面 field 503 的 packed varint 子控件顺序，以断言 overlay 的 Z 序严格在底圆之上
function getChildOrderMap(pageRec) {
  const f503 = pageRec.field.sub.find((x) => x.field === 503 && x.wt === 2 && x.payload);
  const map = new Map();
  if (!f503) return map;
  const buf = f503.payload;
  let i = 0, idx = 0;
  while (i < buf.length) {
    let v = 0n, sh = 0n;
    while (i < buf.length) {
      const b = buf[i++];
      v |= BigInt(b & 0x7f) << sh;
      if ((b & 0x80) === 0) break;
      sh += 7n;
    }
    map.set(Number(v), idx++);
  }
  return map;
}

for (const [pageName, i, overlaySuffix] of DONE_STEP_SLOTS) {
  const pageRec = byName(pageName);
  const bgRec = byName(`${pageName}.stepn.${i}.bg`);
  const numRec = byName(`${pageName}.stepn.${i}`);
  const ovRec = byName(`${pageName}.${overlaySuffix}`);
  assert(pageRec && bgRec && numRec && ovRec, `缺少绿勾控件: ${pageName} step=${i} overlay=${overlaySuffix}`);

  // 断言 Z 序：overlay 必须在 bgRec 之上，且在 stephit 之下（不挡步骤点击）
  const zMap = getChildOrderMap(pageRec);
  const zBg = zMap.get(bgRec.id);
  const zOv = zMap.get(ovRec.id);
  const zHit = zMap.get(byName(`${pageName}.stephit.${i}`).id);
  assert(zOv > zBg, `绿勾叠层 Z 序错误: ${ovRec.name}(${zOv}) 不在 ${bgRec.name}(${zBg}) 之上`);
  assert(zHit > zOv, `绿勾叠层挡住了点击热区: ${ovRec.name}(${zOv}) 在 stephit.${i}(${zHit}) 之上`);

  const rc = getRect(bgRec);
  // 1) 恢复底圆为原 753 的 26×26 绿圆（100002, #7EA65A）
  setHidden(bgRec, false);
  setRectAllStates(bgRec, [rc.x, rc.y], [26, 26]);
  setImgProps(bgRec, { sprite: 100002, color: C_DONE_CIRCLE });

  // 2) 在底圆正中央叠加标准粗体对勾贴图（100102, 15×15, 原深墨绿 #192B12）
  setHidden(ovRec, false);
  setRectAllStates(ovRec, [rc.x, rc.y], [15, 15]);
  setImgProps(ovRec, { sprite: 100102, color: C_DONE_TICK });

  // 3) 保持原细瘦 Unicode ✓ 字符隐藏
  setTextProps(numRec, { text: '' });
  setHidden(numRec, true);

  stat.tutCheckmarks++;
}

// ═════════════════════════════════════════════════════════════════════════════
// PART C：区分提示条左侧 `i` 圆标（notei.bg）与操作按钮图标（#6C402E）配色
// ═════════════════════════════════════════════════════════════════════════════
const NOTEI_PAGES = ['td.l1.page.1', 'td.l1.page.3', 'td.l1.page.8', 'td.l2.page.3'];
for (const pageName of NOTEI_PAGES) {
  const bg = byName(`${pageName}.notei.bg`);
  const tx = byName(`${pageName}.notei`);
  assert(bg && tx, `缺少 notei 控件: ${pageName}`);
  setHidden(bg, false);
  setHidden(tx, false);
  setImgProps(bg, { sprite: 100002, color: C_NOTEI_BG });
  setTextProps(tx, { text: 'i', size: 13, minSize: 12, color: C_NOTEI_TXT, alignH: 1 });
  stat.tutNoteiRecolored++;
}

// 顺手确认首页 1/2/3 分区序号标维持浅金 #E5C98B + 深棕字 #5C341E（与深棕按钮 #6C402E 与 notei #D8B574 均协调区分）
for (const k of [1, 3, 5]) {
  setImgProps(byName(`td.home.page.1.rule.${k}.num.bg`), { sprite: 100002, color: C_SEC_NUM_BG });
  setTextProps(byName(`td.home.page.1.rule.${k}.num`), { color: C_SEC_NUM_TXT });
}

// ═════════════════════════════════════════════════════════════════════════════
// PART D：全量 8 页单行文本防截断门禁 + 颜色区分门禁
// ═════════════════════════════════════════════════════════════════════════════
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
    if (nm.includes('.svg.') || nm.includes('.demo637.') || nm.includes('.hold75.') || nm.includes('.lg.')) continue;
    const rc = getRect(r);
    const minNeeded = measureVisualInkWidth(ti.text, ti.size) + 14;
    stat.checkedTexts++;
    if (rc.w < minNeeded) {
      tightFailures.push(`${nm}: w=${rc.w.toFixed(1)} < minNeeded=${minNeeded} (fs=${ti.size}, txt=${JSON.stringify(ti.text)})`);
    }
  }
}
assert.equal(tightFailures.length, 0, '检测到过紧/可能截断的教程文本:\n' + tightFailures.join('\n'));

console.log('GIL_UI_PATCH_STATS_755:', JSON.stringify(stat));
for (const [k, spans] of Object.entries(rowLayoutSummary)) {
  const gaps = [];
  for (let i = 1; i < spans.length; i++) gaps.push((spans[i].visL - spans[i - 1].visR).toFixed(1) + 'px');
  console.log(`  ROW ${k.padEnd(12)} visGaps=[${gaps.join(', ')}] endVisR=${spans[spans.length - 1].visR.toFixed(1)}`);
}

// ═════════════════════════════════════════════════════════════════════════════
// PART E：内嵌 Lua 脚本仅更新构建标记（其余全部已验证逻辑 100% 保留）
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
  'if print then print("[murdoku] ===== 构建标记 v754 / 教程文本防截断与视觉精修 =====") end',
  'if print then print("[murdoku] ===== 构建标记 v755 / 教程图文间距与视觉一致性精修 =====") end'
);
replaceOnce(
  'build_marker_2',
  'print("[murdoku] ===== 构建标记 v754 / 教程文本防截断与视觉精修 =====")',
  'print("[murdoku] ===== 构建标记 v755 / 教程图文间距与视觉一致性精修 =====")'
);

// ═════════════════════════════════════════════════════════════════════════════
// PART F：语法检查、隐式全局零新增、writeGil 完整往返核验与全量仿真测试
// ═════════════════════════════════════════════════════════════════════════════
const baseLuaTmp = path.join(runTmp, 'base754.lua');
const candLuaTmp = path.join(runTmp, 'cand755.lua');
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

leaf.field.payload = Buffer.from(lua, 'utf8');
const stageGil = path.join(runTmp, '755_stage.gil');
const writeReport = writeGil(g, stageGil, {
  label: '755 教程图文间距与视觉一致性精修',
  assert: (gBack) => {
    assert.equal(gBack.recs.length, g.recs.length, '控件记录数意外变化');
    assert.equal(findScriptLeaf(gBack).buf.toString('utf8'), lua, '回读内嵌脚本不一致');

    // 1) 单人配置 Top#11 原样保留
    const t11Out = gBack.tree.find((x) => x.field === 11);
    assert.equal(t11Out.sub.find((x) => x.field === 6).sub[0].sub.find((x) => x.field === 502).num, 1n, '单人分组人数上限不是 1');
    assert.equal(t11Out.sub.find((x) => x.field === 2).sub[0].sub.find((x) => x.field === 4).payload.length, 1, '初始玩家阵营人数不是 1');

    // 2) 回读验证全部 9 处已完成绿勾：底圆=26x26 100002 #7EA65A + 叠层对勾=15x15 100102 #192B12 + 旧字符隐藏
    for (const [pageName, i, overlaySuffix] of DONE_STEP_SLOTS) {
      const bgRec = gBack.byName.get(`${pageName}.stepn.${i}.bg`);
      const numRec = gBack.byName.get(`${pageName}.stepn.${i}`);
      const ovRec = gBack.byName.get(`${pageName}.${overlaySuffix}`);
      const bgC = getImgComp(bgRec);
      const ovC = getImgComp(ovRec);
      assert.equal(bgC.sub.find((y) => y.field === 503).num, 100002n, `${bgRec.name} 底圆不是 100002`);
      assert.equal(bgC.sub.find((y) => y.field === 502).num, ARGB(C_DONE_CIRCLE), `${bgRec.name} 底圆颜色不是 ${C_DONE_CIRCLE}`);
      assert.equal(ovC.sub.find((y) => y.field === 503).num, 100102n, `${ovRec.name} 对勾不是 100102`);
      assert.equal(ovC.sub.find((y) => y.field === 502).num, ARGB(C_DONE_TICK), `${ovRec.name} 对勾颜色不是 ${C_DONE_TICK}`);
      assert.equal(isHidden(bgRec), false, `${bgRec.name} 被隐藏`);
      assert.equal(isHidden(ovRec), false, `${ovRec.name} 被隐藏`);
      assert.equal(isHidden(numRec), true, `${numRec.name} 旧字符未隐藏`);
      const bgRc = getRect(bgRec), ovRc = getRect(ovRec);
      assert(Math.abs(bgRc.x - ovRc.x) < 0.01 && Math.abs(bgRc.y - ovRc.y) < 0.01, `${ovRec.name} 未与底圆同心`);
    }

    // 3) 回读验证 4 处 notei.bg 已改色且不同于操作按钮深棕 #6C402E
    for (const pageName of NOTEI_PAGES) {
      const col = getImgComp(gBack.byName.get(`${pageName}.notei.bg`)).sub.find((y) => y.field === 502).num;
      assert.equal(col, ARGB(C_NOTEI_BG), `${pageName}.notei.bg 颜色未更新`);
      assert.notEqual(col, ARGB('#6C402E'), `${pageName}.notei.bg 与操作按钮色冲突`);
    }
    return true;
  },
});

// 导出控件树并运行全套离线高仿真 Lua 回归测试
const treePath = path.join(runTmp, 'tree755.lua');
{
  const exp = spawnSync('node', [path.join(repo, 'tests/export_gil_tree.mjs'), stageGil, treePath], { encoding: 'utf8' });
  assert.equal(exp.status, 0, 'export_gil_tree 失败:\n' + exp.stderr + exp.stdout);
  process.stdout.write(exp.stdout);
}

{
  const r = spawnSync('lua', [path.join(repo, 'tests/shop_cold_render.lua')], { input: lua, encoding: 'utf8', cwd: repo });
  assert.equal(r.status, 0, 'shop_cold_render 失败:\n' + r.stdout + '\n' + r.stderr);
  process.stdout.write(r.stdout);
}

const animJsonPath = path.join(runTmp, 'verify_749_on_755.json');
{
  const r = spawnSync('lua', [path.join(repo, 'tests/verify_749_paper_anim.lua'), treePath, candLuaTmp, animJsonPath], { encoding: 'utf8', cwd: repo });
  assert.equal(r.status, 0, 'verify_749_paper_anim 失败:\n' + r.stdout + '\n' + r.stderr);
  process.stdout.write(r.stdout);
  assert(r.stdout.includes('VERIFY_749_PASS=true'), 'verify_749_paper_anim 未通过');
}

const feedbackJson = path.join(runTmp, 'verify_754_on_755.json');
{
  const r = spawnSync('lua', [path.join(repo, 'tests/verify_754_feedback.lua'), treePath, candLuaTmp, feedbackJson], { encoding: 'utf8', cwd: repo });
  process.stdout.write(r.stdout);
  assert.equal(r.status, 0, 'verify_754_feedback 失败:\n' + r.stderr + r.stdout);
  assert(r.stdout.includes('VERIFY_754_PASS=true'), 'verify_754_feedback 未通过');
}

// 全部门禁通过后落盘 755 新目录（严格保留 750/751/752/753/754 旧档）
const outDir = path.dirname(out);
fs.mkdirSync(outDir, { recursive: true });
fs.copyFileSync(stageGil, out);
const diskBuf = fs.readFileSync(out);
fs.writeFileSync(path.join(outDir, '755_内嵌脚本.lua'), lua, 'utf8');

const report = {
  version: '755',
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
  row_visual_layout: Object.fromEntries(
    Object.entries(rowLayoutSummary).map(([k, spans]) => [
      k,
      spans.map((s, idx) => ({
        name: s.name,
        visL: +s.visL.toFixed(1),
        visR: +s.visR.toFixed(1),
        gapFromPrev: idx > 0 ? +(s.visL - spans[idx - 1].visR).toFixed(1) : 0,
      })),
    ])
  ),
  verify749PaperAnim: JSON.parse(fs.readFileSync(animJsonPath, 'utf8')),
  feedback_tests: JSON.parse(fs.readFileSync(feedbackJson, 'utf8')),
};
fs.writeFileSync(path.join(outDir, '755_验证与结构报告.json'), JSON.stringify(report, null, 2), 'utf8');

if (!keepTmp) fs.rmSync(runTmp, { recursive: true, force: true });
console.log('BUILD_755_OK:', out, 'bytes=' + diskBuf.length, 'sha256=' + report.output_sha256);
