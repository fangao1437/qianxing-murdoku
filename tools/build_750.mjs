// tools/build_750.mjs
// 基于 749_背包商店右侧纸张切换动画_v8.gil 构建 750_招募测试反馈修复.gil：
// 1. 第一部分反馈残留修复：
//    a) 结算门槛改为「进入关卡后 90 秒」（不加额外限制；通关任意关立即可结算）
//    b) 关卡内无法提交时通过 hint635.result 给出清晰中文提示 + 确认条第 0 帧精准对齐
//    c) 4:3 平板 block640.modal 全屏缩放 + 弹窗按钮置于 win 之上并关闭 win 射线
//    d) 移动端人物栏透传加固 + 棋盘点击前立刻 _flush_clue_tap() + 棋盘双击改用引擎帧时间 self.now(0.45s)
// 2. 第二部分反馈优化（聚焦教程、文本大小与颜色对比、图例底色）：
//    e) 图例与房间底色全面统一为高区分度低饱和复古色板（大屋暖米黄 / 内室雾灰蓝 / 外间鼠尾草绿 / 4房淡薰衣草紫）
//    f) 教程精简与重构：首页 5 挤卡→3 通栏大卡；第一关 8 页→4 页（page_map={1,3,7,8}）；第二关 4 页→3 页（page_map={2,3,4}），大白话讲透规则与假话判据
//    g) 文本大小与颜色对比度全面提升：教程提亮纸底 #F4E9D2 + 深墨字 #231108 + 按钮 18px / 正文 18px；主界面线索卡/行列标/提示/结算字号与对比度同步优化
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import { stateBlocks, pairOf, setPair } from './gil/gilread.mjs';
import { loadTree, findScriptLeaf, writeGil } from './gil/gilwrite.mjs';

const repo = fileURLToPath(new URL('../', import.meta.url));
const runTmp = fs.mkdtempSync(path.join(os.tmpdir(), 'murdoku-750-'));
const keepTmp = process.argv.includes('--keep-tmp');
const overwrite = process.argv.includes('--overwrite');

const base = path.join(repo, '749_背包商店右侧纸张切换动画/749_背包商店右侧纸张切换动画_v8.gil');
const out = path.resolve(
  process.argv[2] && !process.argv[2].startsWith('--')
    ? process.argv[2]
    : path.join(repo, '750_招募测试反馈修复/750_招募测试反馈修复.gil')
);

if (!overwrite) assert(!fs.existsSync(out), '输出已存在，拒绝覆盖（如需覆盖请传 --overwrite）：' + out);

const sha = (b) => createHash('sha256').update(b).digest('hex');
const g = loadTree(base);
assert.equal(
  sha(g.src),
  'f41bee4261f571a048172b181d52b024b03b59ff54531891f52e4081d22cd65f',
  '基准 749_v8 SHA256 不匹配'
);

// ═════════════════════════════════════════════════════════════════════════════
// 辅助函数：精准修改 .gil 控件的文本、字号、文字色、图片色、坐标尺寸、初始隐藏
// ═════════════════════════════════════════════════════════════════════════════
const ARGB = (hex) => BigInt((0xFF000000 | parseInt(hex.replace('#', ''), 16)) >>> 0);

const stat = {
  roomCells: 0,
  roomLegends: 0,
  tutTexts: 0,
  tutColors: 0,
  tutRects: 0,
  tutHidden: 0,
  uiTexts: 0,
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

function getImgColorField(rec) {
  for (const f of rec.field.sub) {
    if (f.field === 505 && f.sub) {
      const s = f.sub.find((x) => x.field === 503 && x.sub);
      const c84 = s && s.sub.find((x) => x.field === 84 && x.sub);
      const f502 = c84 && c84.sub.find((y) => y.field === 502 && y.wt === 0);
      if (f502) return f502;
    }
  }
  return null;
}

function setImgColor(rec, hex) {
  if (!rec) return false;
  const f = getImgColorField(rec);
  if (!f) return false;
  const want = ARGB(hex);
  if (f.num === want) return false;
  f.num = want;
  return true;
}

function setTextProps(rec, { text, size, minSize, color }) {
  if (!rec) return false;
  const t75 = getTextComp(rec);
  if (!t75) return false;
  let changed = false;
  if (text !== undefined) {
    let t510 = t75.sub.find((y) => y.field === 510 && y.sub);
    if (!t510) {
      t510 = { field: 510, wt: 2, sub: [{ field: 501, wt: 2, isText: true, payload: Buffer.alloc(0), len: 0 }] };
      t75.sub.push(t510);
    }
    let t501 = t510.sub.find((y) => y.field === 501);
    if (!t501) {
      t501 = { field: 501, wt: 2, isText: true, payload: Buffer.alloc(0), len: 0 };
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
  return changed;
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
        if (!c17.sub.length) { delete c17.sub; c17.payload = Buffer.alloc(0); }
        return true;
      }
    }
  }
  return false;
}

const byName = (nm) => g.byName.get(nm);
const hideNames = (prefix, list) => {
  for (const suffix of list) {
    const r = byName(prefix + suffix);
    if (r) setHidden(r, true);
  }
};

// ═════════════════════════════════════════════════════════════════════════════
// PART A：图例与教程棋盘房间底色优化（高区分度低饱和复古羊皮纸色板）
// ═════════════════════════════════════════════════════════════════════════════
const ROOM_HEX = {
  1: '#EAD6A8', // 大屋 / 大厅：暖羊皮米黄
  2: '#B6CDE0', // 内室 / 侧廊：冷雾灰蓝
  3: '#BAD5B4', // 外间 / 库房：柔鼠尾草绿
  4: '#D2C0DC', // 4号房（第2关内室）：淡薰衣草紫
};
const OLD_ROOM_MAP = new Map([
  [ARGB('#e6c483'), ROOM_HEX[1]],
  [ARGB('#d5c39d'), ROOM_HEX[2]],
  [ARGB('#dbcba3'), ROOM_HEX[3]],
  [ARGB('#c9ac6d'), ROOM_HEX[4]],
]);

// 1) 教程棋盘房间格（仅 td.home.board / td.l1.board / td.l2.board 下的 svg.*）
for (const r of g.recs) {
  const nm = r.name || '';
  if (/^td\.(home|l1|l2)\.board\.svg\.\d+$/.test(nm)) {
    const f = getImgColorField(r);
    if (f && OLD_ROOM_MAP.has(f.num)) {
      if (setImgColor(r, OLD_ROOM_MAP.get(f.num))) stat.roomCells++;
    }
  }
}

// 2) 教程各页图例色块 lg.0..lg.3（含全部页面确保一致）
for (const r of g.recs) {
  const nm = r.name || '';
  const m = nm.match(/^td\.(home|l1|l2)\.page\.(\d+)\.lg\.([0-3])$/);
  if (!m) continue;
  const idx = Number(m[3]);
  // td.home 与 td.l1 的 lg.3 是“墙”(#47271a)，只改 lg.0..2；td.l2 有 4 间屋 lg.0..3
  if ((m[1] === 'home' || m[1] === 'l1') && idx === 3) continue;
  if (setImgColor(r, ROOM_HEX[idx + 1])) stat.roomLegends++;
}

// ═════════════════════════════════════════════════════════════════════════════
// PART B：教程整体配色提亮、字号放大、页数精简与版面重构
// ═════════════════════════════════════════════════════════════════════════════
const C_PAPER_MAIN = '#F4E9D2';   // 主卡片明朗浅米纸（原暗土黄 #C9AC6D）
const C_PAPER_SUB  = '#EAE0C8';   // 次卡片（chips/note）柔和米白
const C_PAPER_CLUE = '#F8EDD2';   // 线索引用卡暖羊皮
const C_BORDER     = '#7D5333';   // 柔和深棕边框
const C_INK        = '#231108';   // 主正文深墨黑棕（对比度 >12:1）
const C_INK_SUB    = '#4A2816';   // 次要说明深棕（对比度 >8:1）
const C_ACCENT     = '#B82914';   // 朱砂红强调（对比度 >5.6:1）
const C_GREEN_TXT  = '#1D6A36';   // 高对比深翠绿
const C_BTN_PREV   = '#EFE0BE';   // 上一步浅金底
const C_BTN_NEXT   = '#C83B12';   // 下一步深朱红底
const C_WHITE_WARM = '#FFF9E8';   // 深底白字
const C_TAG_L1     = '#456336';   // l1 步骤标签深橄榄底
const C_TAG_L2     = '#8C2D19';   // l2 步骤标签深砖红底
const C_CHIP_BG    = '#DDE6CC';   // 摘要胶囊浅草绿底

// 先对全部教程展示页做统一的底色提亮与通用文字放大提对比
const ACTIVE_PAGES = [
  'td.home.page.1',
  'td.l1.page.1', 'td.l1.page.3', 'td.l1.page.7', 'td.l1.page.8',
  'td.l2.page.2', 'td.l2.page.3', 'td.l2.page.4',
];

for (const pName of ACTIVE_PAGES) {
  const pRec = byName(pName);
  assert(pRec, '缺少教程页: ' + pName);
  const isL2 = pName.startsWith('td.l2.');

  // 卡片底色提亮
  for (const [k, hex] of [
    ['main', C_PAPER_MAIN], ['main.border', C_BORDER],
    ['chips', C_PAPER_SUB], ['chips.border', C_BORDER],
    ['note', C_PAPER_SUB], ['note.border', C_BORDER],
    ['clue', C_PAPER_CLUE], ['clue.border', C_BORDER],
    ['prevbg', C_BTN_PREV], ['nextbg', C_BTN_NEXT],
    ['tagbg', isL2 ? C_TAG_L2 : C_TAG_L1],
  ]) {
    if (setImgColor(byName(`${pName}.${k}`), hex)) stat.tutColors++;
  }
  for (let i = 0; i <= 2; i++) {
    if (setImgColor(byName(`${pName}.chip.${i}`), C_CHIP_BG)) stat.tutColors++;
    if (setTextProps(byName(`${pName}.chipt.${i}`), { size: 17, minSize: 15, color: C_INK })) stat.tutTexts++;
  }

  // 顶栏/底栏/图例/说明统一放大字号与提对比
  setTextProps(byName(`${pName}.eyebrow`), { size: 18, minSize: 16, color: C_ACCENT });
  setTextProps(byName(`${pName}.title`), { size: 28, minSize: 24, color: C_INK });
  setTextProps(byName(`${pName}.sub`), { size: 18, minSize: 16, color: C_INK_SUB });
  setTextProps(byName(`${pName}.stepnum.0`), { size: 18, minSize: 16, color: C_INK_SUB });
  setTextProps(byName(`${pName}.stepnum.1`), { size: 19, minSize: 16, color: C_ACCENT });
  setTextProps(byName(`${pName}.stepnum.2`), { size: 18, minSize: 16, color: C_INK_SUB });

  setTextProps(byName(`${pName}.tag`), { size: 17, minSize: 15, color: C_WHITE_WARM });
  setTextProps(byName(`${pName}.heading`), { size: 26, minSize: 22, color: C_INK });
  setTextProps(byName(`${pName}.chipsk`), { size: 15, minSize: 14, color: C_INK_SUB });
  setTextProps(byName(`${pName}.cluek`), { size: 15, minSize: 14, color: C_INK_SUB });
  setTextProps(byName(`${pName}.cluename`), { size: 17, minSize: 15, color: C_INK_SUB });
  setTextProps(byName(`${pName}.cluesay.0`), { size: 18, minSize: 16, color: C_INK });
  setTextProps(byName(`${pName}.notet`), { size: 17, minSize: 15, color: C_INK });

  setTextProps(byName(`${pName}.legendtitle`), { size: 19, minSize: 17, color: C_INK });
  for (let i = 0; i <= 12; i++) {
    const lgt = byName(`${pName}.lgt.${i}`);
    if (lgt) setTextProps(lgt, { size: 17, minSize: 15, color: C_INK });
  }
  setTextProps(byName(`${pName}.caption`), { size: 17, minSize: 15, color: C_INK });
  setTextProps(byName(`${pName}.coord`), { size: 17, minSize: 15, color: C_INK_SUB });

  // 底栏三大操作文字显著放大（13 -> 16/18）
  setTextProps(byName(`${pName}.skip`), { size: 16, minSize: 14, color: C_INK_SUB });
  setTextProps(byName(`${pName}.prevtext`), { size: 18, minSize: 16, color: C_INK });
  setTextProps(byName(`${pName}.nexttext`), { size: 18, minSize: 16, color: C_WHITE_WARM });
}

// ── B1. 首页教程 td.home.page.1：5 张拥挤小卡 → 3 张通栏舒朗大卡 ─────────────────
{
  const p = 'td.home.page.1.';
  setTextProps(byName(p + 'sub'), {
    text: '三分钟上手：每行每列各站一人，用线索排除定位，揪出盗窃者',
    size: 18, minSize: 16, color: C_INK_SUB,
  });

  // 隐藏原第 2、4 卡片与所有零碎小图标/拆行文本
  hideNames(p, [
    'rule.2.border', 'rule.2', 'rule.2.num.bg', 'rule.2.num', 'rule.2.title',
    'rule.2.body.0.0', 'rule.2.body.1.0', 'rule.2.body.2.0',
    'rule.4.border', 'rule.4', 'rule.4.num.bg', 'rule.4.num', 'rule.4.title',
    'rule.4.body.0.0', 'rule.4.body.1.0', 'rule.4.body.2.0', 'rule.4.body.3.0',
    'rule.1.body.3.0',
    'ico.submit.bg', 'ico.submit', 'ico.submit.t',
    'ico.undo.bg', 'ico.undo', 'ico.undo.t',
    'ico.redo.bg', 'ico.redo', 'ico.redo.t',
    'help619.icon',
  ]);

  // 通栏卡片 1（Y=124, H=142）：目标与基础规则
  setImgColor(byName(p + 'rule.1'), C_PAPER_MAIN);
  setImgColor(byName(p + 'rule.1.border'), C_BORDER);
  setRectAllStates(byName(p + 'rule.1.border'), [-341.9, 124], [717.8, 144]);
  setRectAllStates(byName(p + 'rule.1'),        [-341.9, 124], [715.8, 142]);
  setRectAllStates(byName(p + 'rule.1.num.bg'), [-667.6, 170], [32, 32]);
  setRectAllStates(byName(p + 'rule.1.num'),    [-667.6, 170], [42, 36]);
  setTextProps(byName(p + 'rule.1.num'), { text: '1', size: 18, minSize: 16, color: '#FFD26A' });
  setRectAllStates(byName(p + 'rule.1.title'),  [-314, 171], [636, 42]);
  setTextProps(byName(p + 'rule.1.title'), { text: '目标：每行每列各一人，找对盗窃者', size: 21, minSize: 18, color: C_INK });
  setRectAllStates(byName(p + 'rule.1.body.0.0'), [-342, 132], [664, 36]);
  setTextProps(byName(p + 'rule.1.body.0.0'), { text: '• 每人（含受害者 V）各占一格，放人后同行同列自动打叉', size: 18, minSize: 16, color: C_INK });
  setRectAllStates(byName(p + 'rule.1.body.1.0'), [-342, 100], [664, 36]);
  setTextProps(byName(p + 'rule.1.body.1.0'), { text: '• 椅子、地毯可站人；桌子、植物等不可站（见关内注释）', size: 18, minSize: 16, color: C_INK });
  setRectAllStates(byName(p + 'rule.1.body.2.0'), [-342, 68], [664, 36]);
  setTextProps(byName(p + 'rule.1.body.2.0'), { text: '• 摆满后点右侧「提交」：找对盗窃者即胜，全对完美通关', size: 18, minSize: 16, color: C_ACCENT });

  // 通栏卡片 2（Y=-36, H=142）：房间、相邻与盗窃者规则
  setImgColor(byName(p + 'rule.3'), C_PAPER_MAIN);
  setImgColor(byName(p + 'rule.3.border'), C_BORDER);
  setRectAllStates(byName(p + 'rule.3.border'), [-341.9, -36], [717.8, 144]);
  setRectAllStates(byName(p + 'rule.3'),        [-341.9, -36], [715.8, 142]);
  setRectAllStates(byName(p + 'rule.3.num.bg'), [-667.6, 10], [32, 32]);
  setRectAllStates(byName(p + 'rule.3.num'),    [-667.6, 10], [42, 36]);
  setTextProps(byName(p + 'rule.3.num'), { text: '2', size: 18, minSize: 16, color: '#FFD26A' });
  setRectAllStates(byName(p + 'rule.3.title'),  [-314, 11], [636, 42]);
  setTextProps(byName(p + 'rule.3.title'), { text: '核心规则：「旁边 / 隔壁」与盗窃者', size: 21, minSize: 18, color: C_INK });
  setRectAllStates(byName(p + 'furniture617.0'), [-342, -28], [664, 36]);
  setTextProps(byName(p + 'furniture617.0'), { text: '• 旁边 = 上下左右相邻格；同屋直接算，跨屋须有橙色门', size: 18, minSize: 16, color: C_INK });
  setRectAllStates(byName(p + 'furniture617.1'), [-342, -60], [664, 36]);
  setTextProps(byName(p + 'furniture617.1'), { text: '• 盗窃者必在与受害者有门相邻、且无辜人数最多的屋里', size: 18, minSize: 16, color: C_ACCENT });
  setRectAllStates(byName(p + 'furniture617.2'), [-342, -92], [664, 36]);
  setTextProps(byName(p + 'furniture617.2'), { text: '• 第二关起至多有 1 句假话，且只有盗窃者可能说谎', size: 18, minSize: 16, color: C_INK });

  // 通栏卡片 3（Y=-196, H=142）：三招操作手势
  setImgColor(byName(p + 'rule.5'), C_PAPER_MAIN);
  setImgColor(byName(p + 'rule.5.border'), C_BORDER);
  setRectAllStates(byName(p + 'rule.5.border'), [-341.9, -196], [717.8, 144]);
  setRectAllStates(byName(p + 'rule.5'),        [-341.9, -196], [715.8, 142]);
  setRectAllStates(byName(p + 'rule.5.num.bg'), [-667.6, -150], [32, 32]);
  setRectAllStates(byName(p + 'rule.5.num'),    [-667.6, -150], [42, 36]);
  setTextProps(byName(p + 'rule.5.num'), { text: '3', size: 18, minSize: 16, color: '#FFD26A' });
  setRectAllStates(byName(p + 'rule.5.title'),  [-314, -149], [636, 42]);
  setTextProps(byName(p + 'rule.5.title'), { text: '操作：选人、三种放棋与标假', size: 21, minSize: 18, color: C_INK });
  setRectAllStates(byName(p + 'rule.5.body.0.0'), [-342, -188], [664, 36]);
  setTextProps(byName(p + 'rule.5.body.0.0'), { text: '• 点左侧线索卡选人并高亮提示位置；双击卡片可标记为假', size: 18, minSize: 16, color: C_INK });
  setRectAllStates(byName(p + 'rule.5.body.1.1'), [-342, -220], [664, 36]);
  setTextProps(byName(p + 'rule.5.body.1.1'), { text: '• 棋盘手势：轻点 = 笔记｜双击 = 预放｜长按 = 正式落子', size: 18, minSize: 16, color: C_ACCENT });
  setRectAllStates(byName(p + 'rule.5.body.2.0'), [-342, -252], [664, 36]);
  setTextProps(byName(p + 'rule.5.body.2.0'), { text: '• 摆错了随时点右侧「撤销 / 重做」，卡关可点右下「提示」', size: 18, minSize: 16, color: C_INK });
}

// 辅助函数：把一页顶部步骤条重构为 N 个宽大居中胶囊（隐藏其余步骤）
function layoutStepBar(pageName, totalSteps, activeIdx, labels, rawMax) {
  const w = totalSteps === 4 ? 220 : 240;
  const gap = totalSteps === 4 ? 24 : 28;
  const totalW = totalSteps * w + (totalSteps - 1) * gap;
  const startX = -totalW / 2 + w / 2;

  setTextProps(byName(`${pageName}.stepnum.1`), { text: String(activeIdx), size: 19, minSize: 16, color: C_ACCENT });
  setTextProps(byName(`${pageName}.stepnum.2`), { text: ` / ${totalSteps} 步`, size: 18, minSize: 16, color: C_INK_SUB });

  for (let i = 1; i <= rawMax; i++) {
    const step = byName(`${pageName}.step.${i}`);
    const nbg  = byName(`${pageName}.stepn.${i}.bg`);
    const num  = byName(`${pageName}.stepn.${i}`);
    const txt  = byName(`${pageName}.stept.${i}`);
    const hit  = byName(`${pageName}.stephit.${i}`);
    if (i > totalSteps) {
      for (const c of [step, nbg, num, txt, hit]) if (c) setHidden(c, true);
      continue;
    }
    const cx = startX + (i - 1) * (w + gap);
    const isCur = i === activeIdx;
    const isDone = i < activeIdx;
    setRectAllStates(step, [cx, 216.2], [w, 43.1]);
    setRectAllStates(hit,  [cx, 216.2], [w, 43.1]);
    setRectAllStates(nbg,  [cx - w / 2 + 24, 216.2], [26, 26]);
    setRectAllStates(num,  [cx - w / 2 + 24, 216.2], [44, 36]);
    setRectAllStates(txt,  [cx + 14, 216.2], [w - 56, 36]);

    setImgColor(step, isCur ? '#8C2D19' : (isDone ? '#9A6B38' : '#C8AD82'));
    setImgColor(nbg,  isCur ? '#F5A623' : (isDone ? '#7EA65A' : '#EFE0BE'));
    setTextProps(num, {
      text: isDone ? '✓' : String(i),
      size: 16, minSize: 14,
      color: isCur ? C_INK : (isDone ? '#192B12' : C_INK_SUB),
    });
    setTextProps(txt, {
      text: labels[i - 1],
      size: 17, minSize: 15,
      color: (isCur || isDone) ? C_WHITE_WARM : C_INK,
    });
  }
}

// ── B2. 第一关教程 td.l1：8 页 → 精简为 4 页（逻辑 1..4 对应原始页 1, 3, 7, 8）────
const L1_STEPS = ['看图与选人', '三种放人手势', '锁定盗窃者', '提交与提示'];

// L1 逻辑第 1/4 步（原 td.l1.page.1）：看图与选人
{
  const p = 'td.l1.page.1';
  layoutStepBar(p, 4, 1, L1_STEPS, 8);
  setTextProps(byName(`${p}.title`), { text: '四步快速上手', size: 28, minSize: 24, color: C_INK });
  setTextProps(byName(`${p}.tag`), { text: '第 1 / 4 步 · 看图与选人', size: 17, minSize: 15, color: C_WHITE_WARM });
  setRectAllStates(byName(`${p}.tagbg`), [-576, 160], [214, 32]);
  setRectAllStates(byName(`${p}.tag`),   [-576, 160], [220, 36]);
  setTextProps(byName(`${p}.heading`), { text: '认识棋盘，点线索卡选人', size: 25, minSize: 22, color: C_INK });

  hideNames(`${p}.`, ['body.1.1', 'body.1.2', 'help619.icon']);
  setRectAllStates(byName(`${p}.body.0.0`), [-342, 68], [664, 38]);
  setTextProps(byName(`${p}.body.0.0`), { text: '• 左边是线索卡，中间是棋盘，右边是操作工具', size: 18, minSize: 16, color: C_INK });
  setRectAllStates(byName(`${p}.body.1.0`), [-342, 30], [664, 38]);
  setTextProps(byName(`${p}.body.1.0`), { text: '• 三色区分三间屋；粗线是墙，橙色是门（门连通才算相邻）', size: 18, minSize: 16, color: C_ACCENT });
  setRectAllStates(byName(`${p}.body.2.0`), [-342, -8], [664, 38]);
  setTextProps(byName(`${p}.body.2.0`), { text: '• 点一张线索卡即选中该人，棋盘同步亮出提示范围', size: 18, minSize: 16, color: C_INK });

  setTextProps(byName(`${p}.chipsk`), { text: '本关场地', size: 15, minSize: 14, color: C_INK_SUB });
  setTextProps(byName(`${p}.chipt.0`), { text: '5×5 · 5 人', size: 17, minSize: 15, color: C_INK });
  setTextProps(byName(`${p}.chipt.1`), { text: '三色三间屋', size: 17, minSize: 15, color: C_INK });
  setRectAllStates(byName(`${p}.chip.1`),  [-455, -158], [126, 36]);
  setRectAllStates(byName(`${p}.chipt.1`), [-455, -158], [126, 36]);
  setRectAllStates(byName(`${p}.chip.2`),  [-318, -158], [126, 36]);
  setRectAllStates(byName(`${p}.chipt.2`), [-318, -158], [126, 36]);
  setTextProps(byName(`${p}.chipt.2`), { text: '三扇门连通', size: 17, minSize: 15, color: C_INK });
  setTextProps(byName(`${p}.notet`), { text: '受害者（V）也要摆进棋盘，别忘了给他留位置', size: 17, minSize: 15, color: C_INK });
}

// L1 逻辑第 2/4 步（原 td.l1.page.3）：三种放人手势
{
  const p = 'td.l1.page.3';
  layoutStepBar(p, 4, 2, L1_STEPS, 8);
  setTextProps(byName(`${p}.title`), { text: '四步快速上手', size: 28, minSize: 24, color: C_INK });
  setTextProps(byName(`${p}.tag`), { text: '第 2 / 4 步 · 三种放人手势', size: 17, minSize: 15, color: C_WHITE_WARM });
  setRectAllStates(byName(`${p}.tagbg`), [-568, 160], [230, 32]);
  setRectAllStates(byName(`${p}.tag`),   [-568, 160], [236, 36]);
  setTextProps(byName(`${p}.heading`), { text: '轻点笔记 · 双击预放 · 长按落子', size: 25, minSize: 22, color: C_INK });

  // 隐藏零碎拼句控件，改用 4 条整行清爽短句
  hideNames(`${p}.`, [
    'body.0.1.key610.1', 'body.0.1.key610.2', 'body.0.1.key610.3', 'body.0.1.key610.4',
    'body.1.0.key610.1', 'body.1.0.key610.2', 'body.1.0.key610.3', 'body.1.0.key610.4',
    'ico.undo.bg', 'ico.undo', 'ico.undo.t',
    'ico.redo.bg', 'ico.redo', 'ico.redo.t',
  ]);
  setRectAllStates(byName(`${p}.body.0.0`), [-342, 68], [664, 36]);
  setTextProps(byName(`${p}.body.0.0`), { text: '• 轻点空格：写铅笔笔记，不占位，方便记录候选格', size: 18, minSize: 16, color: C_INK });
  setRectAllStates(byName(`${p}.body.0.1`), [-342, 34], [664, 36]);
  setTextProps(byName(`${p}.body.0.1`), { text: '• 双击空格：快速预放置（先占位，同时保留此人的其他笔记）', size: 18, minSize: 16, color: C_ACCENT });
  setRectAllStates(byName(`${p}.body.1.0`), [-342, 0], [664, 36]);
  setTextProps(byName(`${p}.body.1.0`), { text: '• 长按空格：黄圈走满后松手正式落子，并清除此人多余笔记', size: 18, minSize: 16, color: C_INK });
  setRectAllStates(byName(`${p}.body.2.0`), [-342, -34], [664, 36]);
  setTextProps(byName(`${p}.body.2.0`), { text: '• 落子后自动给同行同列打叉，不再重复站人', size: 18, minSize: 16, color: C_INK_SUB });
  setHidden(byName(`${p}.note.rule`), true);

  setRectAllStates(byName(`${p}.notet`), [-327, -218], [640, 36]);
  setTextProps(byName(`${p}.notet`), { text: '摆错了？右侧随时可点「撤销 / 重做 / 重置」', size: 17, minSize: 15, color: C_INK });
}

// L1 逻辑第 3/4 步（原 td.l1.page.7）：核心规则——房间人数与锁定盗窃者
{
  const p = 'td.l1.page.7';
  layoutStepBar(p, 4, 3, L1_STEPS, 8);
  setTextProps(byName(`${p}.title`), { text: '四步快速上手', size: 28, minSize: 24, color: C_INK });
  setTextProps(byName(`${p}.tag`), { text: '第 3 / 4 步 · 锁定盗窃者', size: 17, minSize: 15, color: C_WHITE_WARM });
  setRectAllStates(byName(`${p}.tagbg`), [-576, 160], [214, 32]);
  setRectAllStates(byName(`${p}.tag`),   [-576, 160], [220, 36]);
  setTextProps(byName(`${p}.heading`), { text: '多出两种摆法？用房间规则定生死', size: 25, minSize: 22, color: C_INK });

  setRectAllStates(byName(`${p}.body.0.0`), [-342, 68], [664, 36]);
  setTextProps(byName(`${p}.body.0.0`), { text: '• 先按线索逐一排除：本关 A、B、C 锁死后，D 和 V 还剩 2 种摆法', size: 18, minSize: 16, color: C_INK });
  setRectAllStates(byName(`${p}.body.1.0`), [-342, 36], [664, 36]);
  setTextProps(byName(`${p}.body.1.0`), { text: '• 房间规则：盗窃者必在与受害者有门相邻、无辜人数最多的屋', size: 18, minSize: 16, color: C_ACCENT });
  setRectAllStates(byName(`${p}.body.2.0`), [-342, 4], [664, 36]);
  setTextProps(byName(`${p}.body.2.0`), { text: '• 本例大屋有 2 名无辜者、外间仅 1 人 ⇒ D 只能在大屋 (1,3)', size: 18, minSize: 16, color: C_INK });
  setRectAllStates(byName(`${p}.body.3.0`), [-342, -26], [664, 36]);
  setTextProps(byName(`${p}.body.3.0`), { text: '• 谁原本有多个可选格、靠房间规则才定死，谁就是盗窃者！', size: 18, minSize: 16, color: C_ACCENT });

  setTextProps(byName(`${p}.cluename`), { text: '本关结论：A、B、C 全程唯一，只有 D 有选择余地', size: 17, minSize: 15, color: C_INK_SUB });
  setRectAllStates(byName(`${p}.cluesay.0`), [-342, -228], [600, 36]);
  setTextProps(byName(`${p}.cluesay.0`), { text: '因此盗窃者 = D（顾客），确定位置 D=(1,3)、V=(4,5)', size: 18, minSize: 16, color: C_INK });
  setTextProps(byName(`${p}.rule617.0`), { text: '注：第一关全员说真话；第二关起至多有 1 句假话（仅盗窃者可能说谎）', size: 15, minSize: 14, color: C_INK_SUB });
}

// L1 逻辑第 4/4 步（原 td.l1.page.8）：提交与提示
{
  const p = 'td.l1.page.8';
  layoutStepBar(p, 4, 4, L1_STEPS, 8);
  setTextProps(byName(`${p}.title`), { text: '四步快速上手', size: 28, minSize: 24, color: C_INK });
  setTextProps(byName(`${p}.tag`), { text: '第 4 / 4 步 · 提交与提示', size: 17, minSize: 15, color: C_WHITE_WARM });
  setRectAllStates(byName(`${p}.tagbg`), [-576, 160], [214, 32]);
  setRectAllStates(byName(`${p}.tag`),   [-576, 160], [220, 36]);
  setTextProps(byName(`${p}.heading`), { text: '摆满点右侧提交，卡关可用提示', size: 25, minSize: 22, color: C_INK });

  hideNames(`${p}.`, [
    'body.1.0', 'body.1.1', 'body.1.2', 'body.x5', 'body.x6',
    'ico.submit.bg', 'ico.submit', 'ico.submit.t',
    'ico.hint.bg', 'ico.hint', 'ico.hint.t',
  ]);
  setRectAllStates(byName(`${p}.body.0.0`), [-342, 68], [664, 38]);
  setTextProps(byName(`${p}.body.0.0`), { text: '• 全部 5 人摆上棋盘后，点右侧「提交箭头」再点「确认」', size: 18, minSize: 16, color: C_INK });
  setRectAllStates(byName(`${p}.body.2.0`), [-342, 30], [664, 38]);
  setTextProps(byName(`${p}.body.2.0`), { text: '• 判题反馈：绿圈 = 位置正确，红圈 = 位置有误', size: 18, minSize: 16, color: C_ACCENT });
  setRectAllStates(byName(`${p}.body.x7`),  [-342, -8], [664, 38]);
  setTextProps(byName(`${p}.body.x7`),  { text: '• 找对盗窃者即过关，全部人物都摆对即为完美通关！', size: 18, minSize: 16, color: C_INK });

  setImgColor(byName(`${p}.chip.0`), '#D8EED9');
  setTextProps(byName(`${p}.chipt.0`), { text: '绿圈 = 摆对', size: 17, minSize: 15, color: C_GREEN_TXT });
  setImgColor(byName(`${p}.chip.1`), '#F7DAD4');
  setTextProps(byName(`${p}.chipt.1`), { text: '红圈 = 摆错', size: 17, minSize: 15, color: C_ACCENT });
  setRectAllStates(byName(`${p}.notet`), [-327, -218], [640, 36]);
  setTextProps(byName(`${p}.notet`), { text: '卡住了？点右下角「提示」可揭示位置(1次)或验真假(2次)', size: 17, minSize: 15, color: C_INK });
}

// ── B3. 第二关教程 td.l2：4 页 → 精简为 3 页（逻辑 1..3 对应原始页 2, 3, 4）────
const L2_STEPS = ['假话规则', '如何抓谎', '锁定提交'];

// L2 逻辑第 1/3 步（原 td.l2.page.2）：假话规则（大白话讲透，并隐藏第 1 页的 prevbg/prevtext）
{
  const p = 'td.l2.page.2';
  layoutStepBar(p, 3, 1, L2_STEPS, 4);
  hideNames(`${p}.`, ['prevbg', 'prevtext']);
  setTextProps(byName(`${p}.title`), { text: '新机制：抓出假线索', size: 28, minSize: 24, color: C_INK });
  setTextProps(byName(`${p}.tag`), { text: '第 1 / 3 步 · 假话规则', size: 17, minSize: 15, color: C_WHITE_WARM });
  setRectAllStates(byName(`${p}.tagbg`), [-576, 160], [214, 32]);
  setRectAllStates(byName(`${p}.tag`),   [-576, 160], [220, 36]);
  setTextProps(byName(`${p}.heading`), { text: '至多 1 句假话，且只可能来自盗窃者', size: 25, minSize: 22, color: C_INK });

  setRectAllStates(byName(`${p}.rewrite617.3`), [-342, 74], [664, 36]);
  setTextProps(byName(`${p}.rewrite617.3`), { text: '• 本关起至多有 1 句假话（不会预告本关有没有假话）', size: 18, minSize: 16, color: C_INK });
  setRectAllStates(byName(`${p}.rewrite617.2`), [-342, 42], [664, 36]);
  setTextProps(byName(`${p}.rewrite617.2`), { text: '• 只有盗窃者本人的卡可能为假；其他人与通用线索必真', size: 18, minSize: 16, color: C_ACCENT });
  setRectAllStates(byName(`${p}.rewrite617.1`), [-342, 10], [664, 36]);
  setTextProps(byName(`${p}.rewrite617.1`), { text: '• 若全真能摆出解（盗窃者有多个可选格），则全员说真话', size: 18, minSize: 16, color: C_INK });
  setRectAllStates(byName(`${p}.rewrite617.0`), [-342, -22], [664, 36]);
  setTextProps(byName(`${p}.rewrite617.0`), { text: '• 只有全真摆不出解时，盗窃者才会说谎来掩饰位置', size: 18, minSize: 16, color: C_ACCENT });

  setTextProps(byName(`${p}.chipt.0`), { text: '至多 1 句假话', size: 17, minSize: 15, color: C_INK });
  setTextProps(byName(`${p}.chipt.1`), { text: '仅盗窃者说谎', size: 17, minSize: 15, color: C_INK });
  setTextProps(byName(`${p}.chipt.2`), { text: '通用线索必真', size: 17, minSize: 15, color: C_INK });
  setTextProps(byName(`${p}.cluename`), { text: '通用线索（黄底卡片）始终为真，可放心先排除', size: 17, minSize: 15, color: C_INK_SUB });
  setRectAllStates(byName(`${p}.cluesay.0`), [-380, -240], [500, 36]);
  setTextProps(byName(`${p}.cluesay.0`), { text: '例如本关「地毯上没有人」→ 5 个地毯格直接全排除', size: 18, minSize: 16, color: C_INK });
}

// L2 逻辑第 2/3 步（原 td.l2.page.3）：如何抓谎（大白话防多解判据 + 右侧 13 行小字精简为 6 行大字）
{
  const p = 'td.l2.page.3';
  layoutStepBar(p, 3, 2, L2_STEPS, 4);
  setTextProps(byName(`${p}.title`), { text: '新机制：抓出假线索', size: 28, minSize: 24, color: C_INK });
  setTextProps(byName(`${p}.tag`), { text: '第 2 / 3 步 · 如何抓谎', size: 17, minSize: 15, color: C_WHITE_WARM });
  setRectAllStates(byName(`${p}.tagbg`), [-576, 160], [214, 32]);
  setRectAllStates(byName(`${p}.tag`),   [-576, 160], [220, 36]);
  setTextProps(byName(`${p}.heading`), { text: '三步抓出唯一假话（避免误判多解）', size: 25, minSize: 22, color: C_INK });

  // 左侧精简为 4 行清爽大字，隐藏拼碎的旧控件
  hideNames(`${p}.`, ['rewrite617.2', 'rewrite617.0', 'body.1.0', 'body.2.0', 'body.2.2', 'ico.hint631', 'note631.tail']);
  setRectAllStates(byName(`${p}.rewrite617.3`), [-342, 70], [664, 36]);
  setTextProps(byName(`${p}.rewrite617.3`), { text: '① 先当全真试推：若出现矛盾或摆不出，说明必有 1 句假话', size: 18, minSize: 16, color: C_INK });
  setRectAllStates(byName(`${p}.rewrite617.1`), [-342, 36], [664, 36]);
  setTextProps(byName(`${p}.rewrite617.1`), { text: '② 关键判据：某条卡为假时，说谎者本人必须仅剩 1 个可行格', size: 18, minSize: 16, color: C_ACCENT });
  setRectAllStates(byName(`${p}.body.0.0`),     [-342, 2], [664, 36]);
  setTextProps(byName(`${p}.body.0.0`),     { text: '   （若设为假后他仍有多个空位可选，则他不是说谎者！）', size: 17, minSize: 15, color: C_INK_SUB });
  setRectAllStates(byName(`${p}.body.2.1`),     [-342, -30], [664, 36]);
  setTextProps(byName(`${p}.body.2.1`),     { text: '③ 同时检验房间人数规则：唯一同时满足的就是真假答案', size: 18, minSize: 16, color: C_INK });

  setRectAllStates(byName(`${p}.notet`), [-327, -94], [640, 36]);
  setTextProps(byName(`${p}.notet`), { text: '拿不准真假？选中线索后点右下角「提示」可验证（每关 2 次）', size: 17, minSize: 15, color: C_INK });
  setTextProps(byName(`${p}.cluename`), { text: '双击线索卡可标「假」做笔记，再次双击取消', size: 18, minSize: 16, color: C_INK });
  setTextProps(byName(`${p}.cluesay.0`), { text: '标假只是推理笔记，不影响最终提交判定', size: 17, minSize: 15, color: C_INK_SUB });

  // 右侧原本 13 行密密麻麻小字 → 精简为 6 行舒适行距大字，隐藏 lgt.6..12
  setTextProps(byName(`${p}.legendtitle`), { text: '本关速览', size: 19, minSize: 17, color: C_ACCENT });
  const rightLines = [
    ['1. 先按全真试推', 118, C_INK],
    ['C(椅子) 与 E(植物旁)', 80, C_INK],
    ['与 D(A在E下方) 冲突', 42, C_ACCENT],
    ['2. 逐条验证唯一格', -10, C_INK],
    ['仅 D 为假时位置唯一', -48, C_ACCENT],
    ['⇒ 锁定 D 是盗窃者', -86, C_GREEN_TXT],
  ];
  for (let i = 0; i < rightLines.length; i++) {
    const c = byName(`${p}.lgt.${i}`);
    setRectAllStates(c, [609, rightLines[i][1]], [236, 38]);
    setTextProps(c, { text: rightLines[i][0], size: 18, minSize: 16, color: rightLines[i][2] });
  }
  for (let i = rightLines.length; i <= 12; i++) {
    const c = byName(`${p}.lgt.${i}`);
    if (c) setHidden(c, true);
  }
}

// L2 逻辑第 3/3 步（原 td.l2.page.4）：锁定提交
{
  const p = 'td.l2.page.4';
  layoutStepBar(p, 3, 3, L2_STEPS, 4);
  setTextProps(byName(`${p}.title`), { text: '新机制：抓出假线索', size: 28, minSize: 24, color: C_INK });
  setTextProps(byName(`${p}.tag`), { text: '第 3 / 3 步 · 锁定提交', size: 17, minSize: 15, color: C_WHITE_WARM });
  setRectAllStates(byName(`${p}.tagbg`), [-576, 160], [214, 32]);
  setRectAllStates(byName(`${p}.tag`),   [-576, 160], [220, 36]);
  setTextProps(byName(`${p}.heading`), { text: '收口：说假话的人，就是盗窃者', size: 25, minSize: 22, color: C_INK });

  hideNames(`${p}.`, ['ico.submit.bg', 'ico.submit']);
  setRectAllStates(byName(`${p}.rewrite617.3`), [-342, 70], [664, 36]);
  setTextProps(byName(`${p}.rewrite617.3`), { text: '• 本关 C、D、E 不能全真，说明其中必有 1 条假线索', size: 18, minSize: 16, color: C_INK });
  setRectAllStates(byName(`${p}.rewrite617.2`), [-342, 36], [664, 36]);
  setTextProps(byName(`${p}.rewrite617.2`), { text: '• 只有 D 说谎时，D 仅剩唯一位置 (2,4) 且符合房间规则', size: 18, minSize: 16, color: C_ACCENT });
  setRectAllStates(byName(`${p}.rewrite617.1`), [-342, 2], [664, 36]);
  setTextProps(byName(`${p}.rewrite617.1`), { text: '• 只有盗窃者可能说谎 ⇒ 直接锁定 D（快递员）是盗窃者', size: 18, minSize: 16, color: C_ACCENT });
  setRectAllStates(byName(`${p}.rewrite617.0`), [-342, -30], [664, 36]);
  setTextProps(byName(`${p}.rewrite617.0`), { text: '• 摆齐全部 6 人，点右侧「提交箭头」完成破案！', size: 18, minSize: 16, color: C_INK });

  setTextProps(byName(`${p}.chipt.0`), { text: '说谎者位置唯一', size: 17, minSize: 15, color: C_INK });
  setTextProps(byName(`${p}.chipt.1`), { text: 'D 说了假话', size: 17, minSize: 15, color: C_ACCENT });
  setTextProps(byName(`${p}.chipt.2`), { text: 'D 就是盗窃者', size: 17, minSize: 15, color: C_GREEN_TXT });
  setTextProps(byName(`${p}.cluename`), { text: '本关假线索：D（快递员）的个人卡', size: 17, minSize: 15, color: C_INK_SUB });
  setTextProps(byName(`${p}.cluesay.0`), { text: '「E 顾客在 A 服务员的上方」→ 实际 E 在第 6 行，为假', size: 18, minSize: 16, color: C_INK });
}

// ═════════════════════════════════════════════════════════════════════════════
// PART C：主界面与关卡内文本大小、颜色对比度与初始 90 秒文案优化
// ═════════════════════════════════════════════════════════════════════════════
// 1) 线索卡模板（clue 下的 who / what / gen.title / gen.body，存在 2 份模板同步修改）
for (const r of g.recs) {
  const nm = r.name || '';
  if (nm === 'who') {
    if (setTextProps(r, { size: 19, minSize: 16, color: '#FFF8EC' })) stat.uiTexts++;
  } else if (nm === 'what') {
    if (setTextProps(r, { size: 21, minSize: 17, color: '#FFFFFF' })) stat.uiTexts++;
  } else if (nm === 'gen.title') {
    if (setTextProps(r, { size: 19, minSize: 16, color: '#2B1408' })) stat.uiTexts++;
  } else if (nm === 'gen.body') {
    if (setTextProps(r, { size: 21, minSize: 17, color: '#2B1408' })) stat.uiTexts++;
  } else if (/^ruler\.[rc]\.\d+$/.test(nm)) {
    if (setTextProps(r, { size: 18, minSize: 15, color: '#FFF9E6' })) stat.uiTexts++;
  }
}

// 2) 关内注释、提示、结算与倒计时文本
for (const [nm, props] of [
  ['help617.title',          { size: 25, minSize: 22, color: '#3B1E0E' }],
  ['help617.body',           { size: 21, minSize: 18, color: '#2B1408' }],
  ['hint635.menu.title',     { size: 24, minSize: 20, color: '#231108' }],
  ['hint635.menu.position',  { size: 20, minSize: 17, color: '#231108' }],
  ['hint635.menu.clue',      { size: 20, minSize: 17, color: '#231108' }],
  ['hint635.result.body',    { size: 23, minSize: 19, color: '#231108' }],
  ['result.msg.1',           { size: 22, minSize: 18, color: '#2B1408' }],
  ['result.msg.2',           { size: 22, minSize: 18, color: '#2B1408' }],
  ['result.msg.3',           { size: 22, minSize: 18, color: '#2B1408' }],
  ['result.settle.countdown', { text: '90秒后可结算', size: 17, minSize: 15, color: '#3B1E0E' }],
  ['modal.settle.countdown',  { text: '90秒后可结算', size: 17, minSize: 15, color: '#3B1E0E' }],
  ['settle.btn.countdown',    { text: '90秒后可结算', size: 17, minSize: 15 }],
]) {
  const r = byName(nm);
  if (r && setTextProps(r, props)) stat.uiTexts++;
}

console.log('GIL_UI_PATCH_STATS:', JSON.stringify(stat));

// ═════════════════════════════════════════════════════════════════════════════
// PART D：内嵌 Lua 脚本精确补丁
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

// ── 1. 构建标记更新 ──────────────────────────────────────────────────────────
replaceOnce(
  'build_marker_1',
  'if print then print("[murdoku] ===== 构建标记 v749_v8 / 基尔霍夫薄板双模态物理弯曲 =====") end',
  'if print then print("[murdoku] ===== 构建标记 v750 / 招募测试反馈核验与综合优化 =====") end'
);
replaceOnce(
  'build_marker_2',
  'print("[murdoku] ===== 构建标记 v749_v8 / 基尔霍夫薄板双模态物理弯曲 =====")',
  'print("[murdoku] ===== 构建标记 v750 / 招募测试反馈核验与综合优化 =====")'
);

// ── 2. 修复 a（按最新要求：结算门槛为「进入关卡后 90 秒」，不加额外限制；通关任意关即解锁）──
replaceOnce(
  'a_settle_advance',
  `function Murdoku.advance_settle_session(dt)
  if not settle_session.unlocked then
    settle_session.elapsed = math.min(60, settle_session.elapsed + math.max(0, tonumber(dt) or 0))
    if settle_session.elapsed >= 60 then settle_session.unlocked = true end
  end
end`,
  `local SETTLE_PLAY_SECONDS750 = 90
function Murdoku.advance_settle_session(dt)
  if not settle_session.unlocked then
    -- 750(a)：进入关卡后开始 90 秒倒计时（不加弹窗/切屏等额外限制）；首页未进关前不推进计时。
    if not settle_session.entered_level then
      local cur = Murdoku.current and Murdoku.current() or nil
      local ctrl = cur and cur.controller
      if ctrl ~= nil and ctrl.screen == nil then
        settle_session.entered_level = true
      end
    end
    if settle_session.entered_level then
      settle_session.elapsed = math.min(SETTLE_PLAY_SECONDS750, settle_session.elapsed + math.max(0, tonumber(dt) or 0))
      if settle_session.elapsed >= SETTLE_PLAY_SECONDS750 then settle_session.unlocked = true end
    end
  end
end`
);

replaceOnce(
  'a_settle_controller_90s',
  `function Controller:settle_seconds_left()
  if self:can_settle() then return 0 end
  local session = self.opts and self.opts.settle_session
  return math.max(1, math.ceil(60 - (session and session.elapsed or self._settle_elapsed or 0)))
end
function Controller:tick(dt)
  if not (self.opts and self.opts.settle_session) and not self._settle_unlocked then
    self._settle_elapsed = math.min(60, (self._settle_elapsed or 0) + math.max(0, dt or 0))
    if self._settle_elapsed >= 60 then self._settle_unlocked = true end
  end`,
  `function Controller:settle_seconds_left()
  if self:can_settle() then return 0 end
  local session = self.opts and self.opts.settle_session
  return math.max(1, math.ceil(90 - (session and session.elapsed or self._settle_elapsed or 0)))
end
function Controller:tick(dt)
  if not (self.opts and self.opts.settle_session) and not self._settle_unlocked then
    if not self._settle_entered and self.screen == nil then self._settle_entered = true end
    if self._settle_entered then
      self._settle_elapsed = math.min(90, (self._settle_elapsed or 0) + math.max(0, dt or 0))
      if self._settle_elapsed >= 90 then self._settle_unlocked = true end
    end
  end`
);

// ── 3. 修复 b（提交未通过时在关卡内弹出可见提示 + 打开确认条当帧零延迟对齐）────────
replaceOnce(
  'b_do_submit_visible_feedback',
  `  if res ~= nil and res.ok then
    local wrong = self:_start_verdict()
    if wrong == nil then
      self:_settle_by_roles()
    elseif wrong > 0 then
      local got, total = core:score()
      self.toast = string.format("摆对了 %d / %d 个，红圈是摆错的位置", got, total)
      self.toast_until = self.now + M.TOAST_SECONDS
    end
  end`,
  `  if res ~= nil and res.ok then
    local wrong = self:_start_verdict()
    if wrong == nil then
      self:_settle_by_roles()
    elseif wrong > 0 then
      local got, total = core:score()
      self.toast = string.format("摆对了 %d / %d 个，红圈是摆错的位置", got, total)
      self.toast_until = self.now + M.TOAST_SECONDS
    end
  else
    -- 750(b)：关内无 toast 文本框，未摆满/冲突无法提交时借用现成 hint635.result 给出清晰提示，杜绝“点确定无反应”。
    local msg = (res and res.message) or "还有人物未摆放到棋盘上"
    self.hint635 = { kind = "message", text = "无法提交：" .. tostring(msg), until_time = (self.now or 0) + 3.5 }
  end`
);

replaceOnce(
  'b_confirm_zero_delay_align',
  `  local pageChanged=page~=st.page
  st.elapsed=st.elapsed+(dt or 0)
  if not force and not pageChanged and st.elapsed<.25 then return end
  st.elapsed=0
  local ok_sz,cw,ch=pcall(game.GetUICanvasSize)
  local valid_sz=ok_sz and type(cw)=='number' and cw>0 and cw<math.huge and type(ch)=='number' and ch>0 and ch<math.huge
  local slot=valid_sz and adapt715r_device() or nil
  local pending=cur and cur.controller and cur.controller.pending
  local pend_act=pending and pending.action or ''`,
  `  local pageChanged=page~=st.page
  local pending=cur and cur.controller and cur.controller.pending
  local pend_act=pending and pending.action or ''
  local pendChanged=pend_act~=st.steady_pend
  st.elapsed=st.elapsed+(dt or 0)
  -- 750(b)：确认卡打开/切换当帧立即执行 follow_confirm717，不再等待 0.25s 节流（稳态 0 开销）。
  if not force and not pageChanged and not pendChanged and st.elapsed<.25 then return end
  st.elapsed=0
  local ok_sz,cw,ch=pcall(game.GetUICanvasSize)
  local valid_sz=ok_sz and type(cw)=='number' and cw>0 and cw<math.huge and type(ch)=='number' and ch>0 and ch<math.huge
  local slot=valid_sz and adapt715r_device() or nil`
);

// ── 4. 修复 c（4:3 平板 block640.modal 满屏缩放 + modal 内按钮层序置于 win 之上）───
replaceOnce(
  'c_modal_cover_and_zorder',
  `    if want and panel and (spec.tag == 'l1' or spec.tag == 'l2' or spec.tag == 'home') then
      local ok, width, height = pcall(function() return game.GetUICanvasSize() end)
      if ok and type(width)=='number' and type(height)=='number' and width>0 and height>0 then
        local sy = (1600*height/width+8)/4096
        if e.coverY ~= sy then
          if pcall(function() panel:SetLocalScale(1608/2048,sy,1) end) then e.coverY=sy end
        end
      end
    elseif not want then e.coverY=nil end`,
  `    if want and panel and (spec.tag == 'l1' or spec.tag == 'l2' or spec.tag == 'home' or spec.tag == 'modal') then
      local ok, width, height = pcall(function() return game.GetUICanvasSize() end)
      if ok and type(width)=='number' and type(height)=='number' and width>0 and height>0 then
        if spec.tag == 'modal' then
          -- 750(c)：block640.modal 静态尺寸为 1600x900，在 4:3 平板（1600x1200）等高画幅下按真实高度满铺遮罩。
          local sy = math.max(1, (1600 * height / width + 8) / 900)
          local sx = 1608 / 1600
          if e.coverY ~= sy then
            if pcall(function() panel:SetLocalScale(sx, sy, 1) end) then e.coverY = sy end
          end
        else
          local sy = (1600*height/width+8)/4096
          if e.coverY ~= sy then
            if pcall(function() panel:SetLocalScale(1608/2048,sy,1) end) then e.coverY=sy end
          end
        end
      end
    elseif not want then e.coverY=nil end`
);

replaceOnce(
  'c_modal_buttons_above_win',
  `      -- 748（B4）：仅当显隐、防穿透与全部置顶均成功才落盘 last_want745；任一抛错下帧立即重试，绝不锁死 59 帧。
      e.last_want745 = ok_all and want or nil`,
  `      if want and spec.tag == 'modal' then
        -- 750(c)：确保 win 容器不抢射线，且结算/退出弹窗交互按钮层序严格位于 win 之上，杜绝平板/各端无法点下一关或退出。
        local win_c = adapter:find('win')
        if win_c ~= nil then
          pcall(function() win_c.raycastTarget = false; win_c.blockRaycast = false end)
        end
        for _, bnm in ipairs({'result.next','result.exit','result.home','result.settle','modal.exit','modal.save','modal.settle','modal.cancel'}) do
          local bc = adapter:find(bnm)
          if bc ~= nil then pcall(e744_last_sib, bc) end
        end
      end
      -- 748（B4）：仅当显隐、防穿透与全部置顶均成功才落盘 last_want745；任一抛错下帧立即重试，绝不锁死 59 帧。
      e.last_want745 = ok_all and want or nil`
);

// ── 5. 修复 d（移动端人物栏透传加固 + 棋盘点击前立刻 flush 选人 + 双击改用引擎帧时钟 self.now）──
replaceOnce(
  'd_cell_double_click_clock',
  `local DOUBLE_CLICK_SECONDS = 0.35`,
  `local DOUBLE_CLICK_SECONDS = 0.35
local CELL_DOUBLE_CLICK_SECONDS = 0.45`
);

replaceOnce(
  'd_on_cell_click_use_engine_now',
  `function Controller:on_cell_click(r, c)
  if r == nil or c == nil then return end
  local core = self.core
  self.now = self.now or 0
  local occupied = core.grid[r][c] ~= nil
  local mode = core.mode
  if (not occupied) and mode == "place" then
    local last = self.last_click
    if last and last.r == r and last.c == c and (gesture_now(self) - last.t) <= DOUBLE_CLICK_SECONDS then
      self.last_click = nil
      if last.did == "x" then
        core:toggle_x(r, c)              
        self.dirty = true
      elseif last.did == "pre" then
        core:undo()                      
        self.dirty = true
      end
      self:do_pre_place(r, c)
      return
    end
  end
  local had = core.grid[r][c]
  local had_selected = core.selected           
  local ok, why = core:tap_cell(r, c)
  if ok then
    self:dismiss_action_confirm()
    if had then
      self:fx(self:cell_id(r, c) .. ".face", M.EFFECTS.ERASE)
      if self.opts.on_clear then self.opts.on_clear(had) end
      self._grid_refill_pending = true
    else
      self:fx(self:cell_id(r, c), core.mode == "x" and M.EFFECTS.XMARK or M.EFFECTS.NOTE)
    end
    if (not occupied) and mode == "place" then
      self.last_click = {
        r = r, c = c, t = gesture_now(self),
        did = had_selected and "pre" or "x",
      }
    end
    self.dirty = true
  else
    if (not occupied) and mode == "place" and self.last_click == nil then
      self.last_click = { r = r, c = c, t = gesture_now(self), did = "none" }
    end
    self:_refuse(r, c, why)
  end
end`,
  `local function cell_click_now(self)
  local t = rawget(M, "TEST_CLOCK")
  if type(t) == "number" then return t end
  -- 750(d)：与长按及线索卡双击保持一致，使用引擎帧累积墙钟时间 self.now，彻底避免真机 os.clock() CPU 时间漂移导致双击失效。
  return (self and rawget(self, "now")) or 0
end
function Controller:on_cell_click(r, c)
  if r == nil or c == nil then return end
  -- 750(d)：点完人物卡后 0.35s 内立即点/双击棋盘，必须先结算挂起的人物选择，避免选不到人或先画 X。
  self:_flush_clue_tap()
  local core = self.core
  self.now = self.now or 0
  local now_t = cell_click_now(self)
  local occupied = core.grid[r][c] ~= nil
  local mode = core.mode
  if (not occupied) and mode == "place" then
    local last = self.last_click
    if last and last.r == r and last.c == c and (now_t - last.t) <= CELL_DOUBLE_CLICK_SECONDS then
      self.last_click = nil
      if last.did == "x" then
        core:toggle_x(r, c)              
        self.dirty = true
      elseif last.did == "pre" then
        core:undo()                      
        self.dirty = true
      end
      self:do_pre_place(r, c)
      return
    end
  end
  local had = core.grid[r][c]
  local had_selected = core.selected           
  local ok, why = core:tap_cell(r, c)
  if ok then
    self:dismiss_action_confirm()
    if had then
      self:fx(self:cell_id(r, c) .. ".face", M.EFFECTS.ERASE)
      if self.opts.on_clear then self.opts.on_clear(had) end
      self._grid_refill_pending = true
    else
      self:fx(self:cell_id(r, c), core.mode == "x" and M.EFFECTS.XMARK or M.EFFECTS.NOTE)
    end
    if (not occupied) and mode == "place" then
      self.last_click = {
        r = r, c = c, t = now_t,
        did = had_selected and "pre" or "x",
      }
    end
    self.dirty = true
  else
    if (not occupied) and mode == "place" and self.last_click == nil then
      self.last_click = { r = r, c = c, t = now_t, did = "none" }
    end
    self:_refuse(r, c, why)
  end
end`
);

replaceOnce(
  'd_flush_clue_tap_on_cell_down',
  `  if event.phase == "down" then
    if a == "click" then self:on_cell_down(event.r, event.c, event.x, event.y) end
    return self.effects
  end`,
  `  if event.phase == "down" then
    if a == "click" then
      self:_flush_clue_tap()
      self:on_cell_down(event.r, event.c, event.x, event.y)
    end
    return self.effects
  end`
);

replaceOnce(
  'd_grid_item_passthrough_and_drag_reset',
  `  local pressed,ox,oy,dragged
  local function listen(kind,fn)
    local e=enum_at("CursorEventType."..kind)
    if e then pcall(function() item:AddCursorEventListener(e,fn) end) end
  end
  local function xy(data)
    if data and data.GetUIPos then return data:GetUIPos() end
  end
  local function moved(data)
    local x,y=xy(data)
    if type(x)=="number" and type(ox)=="number" and ((x-ox)^2+(y-oy)^2)>TAP_MOVE_TOLERANCE^2 then dragged=true end
    if dragged then self._clue_tap=nil end
  end
  listen("CursorDown",function(data) pressed=self:_grid_pos_of_item(grid,item); ox,oy=xy(data); dragged=false end)
  -- Native grid owns dragging. Compare down/up positions to reject swipe clicks.
  listen("CursorUp",moved)
  local ok=pcall(function()
    item:AddCursorEventListener(click,function()
      if adapter._clue_owner and adapter._clue_owner~=self then return end
      if self.screen or self.modal or dragged or (pressed and pressed~=self:_grid_pos_of_item(grid,item)) then
        self._clue_tap=nil
      else self:_on_grid_item_click(adapter,grid,item) end
      pressed,dragged=nil,false
    end)
  end)`,
  `  -- 750(d)：在保留 722_v9「不注册 CursorDrag 由原生网格视窗接管滑动」基础上，
  -- 显式确保卡片允许光标事件向父级网格视窗透传，并为 CursorUp 滑动拦截加时间戳防残留误吞下一次轻点。
  pcall(function() item.disableCursorEventPassthrough = false end)
  local pressed,ox,oy,dragged,drag_at
  local function listen(kind,fn)
    local e=enum_at("CursorEventType."..kind)
    if e then pcall(function() item:AddCursorEventListener(e,fn) end) end
  end
  local function xy(data)
    if data and data.GetUIPos then return data:GetUIPos() end
  end
  local function moved(data)
    local x,y=xy(data)
    if type(x)=="number" and type(ox)=="number" and ((x-ox)^2+(y-oy)^2)>TAP_MOVE_TOLERANCE^2 then
      dragged=true
      drag_at=self.now or 0
    end
    if dragged then self._clue_tap=nil end
  end
  listen("CursorDown",function(data) pressed=self:_grid_pos_of_item(grid,item); ox,oy=xy(data); dragged=false; drag_at=nil end)
  -- Native grid owns dragging. Compare down/up positions to reject swipe clicks.
  listen("CursorUp",moved)
  local ok=pcall(function()
    item:AddCursorEventListener(click,function()
      if adapter._clue_owner and adapter._clue_owner~=self then return end
      local recent_drag = dragged and (drag_at == nil or ((self.now or 0) - drag_at) < 0.5)
      if self.screen or self.modal or recent_drag or (pressed and pressed~=self:_grid_pos_of_item(grid,item)) then
        self._clue_tap=nil
      else self:_on_grid_item_click(adapter,grid,item) end
      pressed,ox,oy,dragged,drag_at=nil,nil,nil,false,nil
    end)
  end)`
);

// ── 6. 优化 e（真实棋盘 Controller.ROOM_COLORS 与教程图例 100% 同步的高区分度色板）──
replaceOnce(
  'e_room_colors_high_contrast',
  `Controller.ROOM_COLORS = {
  { r = 217, g = 205, b = 180 },    
  { r = 195, g = 205, b = 212 },    
  { r = 212, g = 200, b = 188 },    
  { r = 190, g = 207, b = 176 },    
  { r = 224, g = 200, b = 176 },    
  { r = 198, g = 198, b = 210 },    
}`,
  `Controller.ROOM_COLORS = {
  -- 750(e)：与教程图例严格一致的高区分度低饱和复古色板（暖羊皮米黄 / 冷雾灰蓝 / 柔鼠尾草绿 / 淡薰衣草紫 / 暖陶粉杏 / 淡青碧）
  { r = 234, g = 214, b = 168 },
  { r = 182, g = 205, b = 224 },
  { r = 186, g = 213, b = 180 },
  { r = 210, g = 192, b = 220 },
  { r = 228, g = 194, b = 178 },
  { r = 176, g = 213, b = 208 },
}`
);

// ── 7. 优化 f（教程精简页数映射：l1 8页→4页 {1,3,7,8}，l2 4页→3页 {2,3,4}）────────
replaceOnce(
  'f_tutorial_ui_page_map',
  `function M.new(adapter, opts)
  if type(opts) ~= "table" then opts = {} end
  return setmetatable({
    adapter = adapter,
    tag = tostring(opts.tag or "?"),
    root_name = tostring(opts.root or ("td." .. tostring(opts.tag or "?"))),
    pages = tonumber(opts.pages) or 1,
    page = 1,
    open = false,
    inited = false,
    eager_furniture = (opts.eager_furniture == true),
    bound = {},
    log = {},
  }, { __index = M })
end`,
  `function M.new(adapter, opts)
  if type(opts) ~= "table" then opts = {} end
  local pmap = type(opts.page_map) == "table" and opts.page_map or nil
  local pages = pmap and #pmap or (tonumber(opts.pages) or 1)
  local raw_pages = tonumber(opts.raw_pages) or pages
  if pmap then
    for i = 1, #pmap do
      if pmap[i] > raw_pages then raw_pages = pmap[i] end
    end
  end
  return setmetatable({
    adapter = adapter,
    tag = tostring(opts.tag or "?"),
    root_name = tostring(opts.root or ("td." .. tostring(opts.tag or "?"))),
    pages = pages,
    raw_pages = raw_pages,
    page_map = pmap,
    page = 1,
    open = false,
    inited = false,
    eager_furniture = (opts.eager_furniture == true),
    bound = {},
    log = {},
  }, { __index = M })
end
function M:_raw_page(logical_idx)
  local pm = self.page_map
  if pm ~= nil then return pm[logical_idx] or logical_idx end
  return logical_idx
end`
);

replaceOnce(
  'f_tutorial_ui_bind_and_paint',
  `function M:_bind_steps()
  if self.pages < 2 then return end
  self._steps_bound = self._steps_bound or {}
  if self._steps_bound[self.page] then return end
  local prefix = self.root_name .. ".page." .. tostring(self.page)
  local complete = true
  local controls = {}
  local page_ctrl = self:_find(prefix)
  local kids = nil
  if page_ctrl and page_ctrl.GetChildren then pcall(function() kids = page_ctrl:GetChildren() end) end
  if type(kids) == "table" then
    for _, child in ipairs(kids) do
      local name = nil
      pcall(function() name = child.name end)
      if name then controls[name] = child end
    end
  end
  local function bind(name, fn)
    if type(kids) == "table" and controls[name] == nil then return false end
    return self:_bind(name, fn, controls[name])
  end
  for i = 1, self.pages do
    local target = i
    local fn = function() if self.open then self:go(target) end end
    if not bind(prefix .. ".stephit." .. tostring(i), fn) then complete = false end
  end
  if complete then self._steps_bound[self.page] = true end
end
function M:_paint()
  -- 705：两关末页和首页统一文案；控件迟到时下次绘制仍会补写。
  if (self.tag == "l1" or self.tag == "l2") and self.page == self.pages then
    local label = self:_find(self.root_name .. ".page." .. tostring(self.pages) .. ".nexttext")
    if label ~= nil then pcall(function() label.text = "开始办案" end) end
  end
  if self.open then self:_bind_steps() end
  for i = 1, self.pages do
    self:_visible(self.root_name .. ".page." .. tostring(i), i == self.page)
  end
  self:_visible(self.root_name .. ".btn.prev", self.page > 1)
  self:_visible(self.root_name .. ".btn.next", true)
  return self
end`,
  `function M:_bind_steps()
  if self.pages < 2 then return end
  self._steps_bound = self._steps_bound or {}
  if self._steps_bound[self.page] then return end
  local raw_p = self:_raw_page(self.page)
  local prefix = self.root_name .. ".page." .. tostring(raw_p)
  local complete = true
  local controls = {}
  local page_ctrl = self:_find(prefix)
  local kids = nil
  if page_ctrl and page_ctrl.GetChildren then pcall(function() kids = page_ctrl:GetChildren() end) end
  if type(kids) == "table" then
    for _, child in ipairs(kids) do
      local name = nil
      pcall(function() name = child.name end)
      if name then controls[name] = child end
    end
  end
  local function bind(name, fn)
    if type(kids) == "table" and controls[name] == nil then return false end
    return self:_bind(name, fn, controls[name])
  end
  for i = 1, self.pages do
    local target = i
    local fn = function() if self.open then self:go(target) end end
    if not bind(prefix .. ".stephit." .. tostring(i), fn) then complete = false end
  end
  if complete then self._steps_bound[self.page] = true end
end
function M:_paint()
  local cur_raw = self:_raw_page(self.page)
  -- 750(f)：支持精简页数映射，末页统一文案为「开始办案」，隐藏全部非当前物理页。
  if (self.tag == "l1" or self.tag == "l2") and self.page == self.pages then
    local label = self:_find(self.root_name .. ".page." .. tostring(cur_raw) .. ".nexttext")
    if label ~= nil then pcall(function() label.text = "开始办案" end) end
  end
  if self.open then self:_bind_steps() end
  local total_raw = self.raw_pages or self.pages
  for r = 1, total_raw do
    self:_visible(self.root_name .. ".page." .. tostring(r), r == cur_raw)
  end
  self:_visible(self.root_name .. ".btn.prev", self.page > 1)
  self:_visible(self.root_name .. ".btn.next", true)
  return self
end`
);

replaceOnce(
  'f_tut_sets_compact',
  `local TUT_SETS = {
  home = { tag = "home", root = "td.home", text = "td.home", pages = 1 },
  l1   = { tag = "l1",   root = "td.l1",   text = "td.l1",   pages = 8 },
  l2   = { tag = "l2",   root = "td.l2",   text = "td.l2",   pages = 4 },
}`,
  `local TUT_SETS = {
  home = { tag = "home", root = "td.home", text = "td.home", pages = 1, raw_pages = 1 },
  -- 750(f)：精简教程页数，第一关 8 页→4 页，第二关 4 页→3 页
  l1   = { tag = "l1",   root = "td.l1",   text = "td.l1",   pages = 4, raw_pages = 8, page_map = { 1, 3, 7, 8 } },
  l2   = { tag = "l2",   root = "td.l2",   text = "td.l2",   pages = 3, raw_pages = 4, page_map = { 2, 3, 4 } },
}`
);

replaceOnce(
  'f_tutorial_instance_pass_map',
  `    return mod.new(adapter, { tag = spec.tag, root = spec.root, text = spec.text, pages = spec.pages, content = content })`,
  `    return mod.new(adapter, { tag = spec.tag, root = spec.root, text = spec.text, pages = spec.pages, raw_pages = spec.raw_pages, page_map = spec.page_map, content = content })`
);

// ── 静态语法与全局读写门禁（对比 749_v8，零新增全局变量）─────────────────────────
const origLuaPath = path.join(runTmp, '749v8.lua');
const candLuaPath = path.join(runTmp, '750.lua');
fs.writeFileSync(origLuaPath, original, 'utf8');
fs.writeFileSync(candLuaPath, lua, 'utf8');

function luacGlobals(filePath) {
  const res = spawnSync('luac', ['-p', '-l', filePath], { encoding: 'utf8', maxBuffer: 64 * 1024 * 1024 });
  assert.equal(res.status, 0, 'luac 编译失败:\n' + res.stderr);
  const gets = new Set(), sets = new Set();
  for (const line of res.stdout.split(/\r?\n/)) {
    const gm = line.match(/GETTABUP\s+.*_ENV\s+"([^"]+)"/);
    if (gm) gets.add(gm[1]);
    const sm = line.match(/SETTABUP\s+.*_ENV\s+"([^"]+)"/);
    if (sm) sets.add(sm[1]);
  }
  return { gets, sets };
}

const gBase = luacGlobals(origLuaPath);
const gNew = luacGlobals(candLuaPath);
const newGets = [...gNew.gets].filter((x) => !gBase.gets.has(x));
const newSets = [...gNew.sets].filter((x) => !gBase.sets.has(x));
assert.deepEqual(newGets, [], '禁止新增隐式全局读: ' + newGets.join(', '));
assert.deepEqual(newSets, [], '禁止新增隐式全局写: ' + newSets.join(', '));
console.log(`STATIC_GATE_OK: newGets=0 newSets=0 scriptBytes=${Buffer.byteLength(original,'utf8')}->${Buffer.byteLength(lua,'utf8')}`);

// ── 写入临时 .gil 并走 writeGil 完整检查链（零控件增删，逐目标落盘回读断言）──────
leaf.field.payload = Buffer.from(lua, 'utf8');
const stageGil = path.join(runTmp, '750_stage.gil');
const report = writeGil(g, stageGil, {
  label: '750 招募测试反馈综合修复与教程/图例/文本优化',
  assert: (g2) => {
    assert.equal(g2.recs.length, g.recs.length, '控件记录数不得变化');
    const l2 = findScriptLeaf(g2).buf.toString('utf8');
    assert.equal(l2, lua, '回读内嵌脚本与候选脚本不一致');
    // 落盘回读验证：图例内室(#B6CDE0) vs 外间(#BAD5B4) 已高区分度分离
    const lg1 = getImgColorField(g2.byName.get('td.home.page.1.lg.1'));
    const lg2 = getImgColorField(g2.byName.get('td.home.page.1.lg.2'));
    assert.equal(lg1.num, ARGB(ROOM_HEX[2]), '回读 td.home.page.1.lg.1（内室）色值不对');
    assert.equal(lg2.num, ARGB(ROOM_HEX[3]), '回读 td.home.page.1.lg.2（外间）色值不对');
    // 落盘回读验证：按钮字号已从 13 升至 18
    const nt = getTextComp(g2.byName.get('td.l1.page.1.nexttext'));
    const f512 = nt.sub.find((y) => y.field === 512 && y.wt === 0);
    assert.equal(Number(f512.num), 18, '回读 nexttext 字号应为 18');
    // 落盘回读验证：90秒文案
    const cd = getTextComp(g2.byName.get('modal.settle.countdown'));
    const cdTxt = cd.sub.find((y) => y.field === 510).sub.find((y) => y.field === 501).payload.toString('utf8');
    assert.equal(cdTxt, '90秒后可结算', '回读倒计时文案应为 90秒后可结算');
    return true;
  },
});

// ── 导出控件树并执行全套离线高仿真 Lua 回归测试 ──────────────────────────────────
const tree750Path = path.join(runTmp, 'tree750.lua');
const expRes = spawnSync('node', [path.join(repo, 'tests/export_gil_tree.mjs'), stageGil, tree750Path], { encoding: 'utf8' });
assert.equal(expRes.status, 0, '导出控件树失败:\n' + expRes.stderr);
process.stdout.write(expRes.stdout);

// 1) shop_cold_render.lua
const coldRes = spawnSync('lua', [path.join(repo, 'tests/shop_cold_render.lua')], { input: lua, encoding: 'utf8', cwd: repo });
assert.equal(coldRes.status, 0, 'shop_cold_render.lua 失败:\n' + coldRes.stdout + '\n' + coldRes.stderr);
process.stdout.write(coldRes.stdout);

// 2) verify_749_paper_anim.lua（确保不破坏 749v8 纸张动画）
const animJsonPath = path.join(runTmp, 'verify_749_on_750.json');
const animRes = spawnSync('lua', [path.join(repo, 'tests/verify_749_paper_anim.lua'), tree750Path, candLuaPath, animJsonPath], { encoding: 'utf8', cwd: repo });
assert.equal(animRes.status, 0, 'verify_749_paper_anim.lua 失败:\n' + animRes.stdout + '\n' + animRes.stderr);
process.stdout.write(animRes.stdout);
assert(animRes.stdout.includes('VERIFY_749_PASS=true'), 'verify_749_paper_anim 未通过');

// 3) verify_750_feedback.lua（专项回归测试：a/b/c/d + 教程精简翻页 + 图例色板）
const fbJsonPath = path.join(runTmp, 'verify_750_feedback.json');
const fbRes = spawnSync('lua', [path.join(repo, 'tests/verify_750_feedback.lua'), tree750Path, candLuaPath, fbJsonPath], { encoding: 'utf8', cwd: repo });
assert.equal(fbRes.status, 0, 'verify_750_feedback.lua 失败:\n' + fbRes.stdout + '\n' + fbRes.stderr);
process.stdout.write(fbRes.stdout);
assert(fbRes.stdout.includes('VERIFY_750_PASS=true'), 'verify_750_feedback 未通过');

// ── 全部门禁通过，落盘最终产物 ─────────────────────────────────────────────────
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.copyFileSync(stageGil, out);
const outBuf = fs.readFileSync(out);
const outDir = path.dirname(out);
fs.writeFileSync(path.join(outDir, '750_内嵌脚本.lua'), lua, 'utf8');

const summary = {
  version: '750',
  base: path.relative(repo, base),
  baseSha256: sha(g.src),
  out: path.relative(repo, out),
  outSha256: sha(outBuf),
  outBytes: outBuf.length,
  records: g.recs.length,
  fieldDiffs: report.diffs,
  gilPatchStats: stat,
  scriptBytesBefore: Buffer.byteLength(original, 'utf8'),
  scriptBytesAfter: Buffer.byteLength(lua, 'utf8'),
  staticGate: { newGets: 0, newSets: 0 },
  tests: {
    shop_cold_render: true,
    verify_749_paper_anim: JSON.parse(fs.readFileSync(animJsonPath, 'utf8')),
    verify_750_feedback: JSON.parse(fs.readFileSync(fbJsonPath, 'utf8')),
  },
};
fs.writeFileSync(path.join(outDir, '750_验证与结构报告.json'), JSON.stringify(summary, null, 2), 'utf8');

console.log(`BUILD_750_OK: out=${out} bytes=${outBuf.length} sha256=${summary.outSha256} fieldDiffs=${report.diffs}`);

if (!keepTmp) {
  try { fs.rmSync(runTmp, { recursive: true, force: true }); } catch {}
}
