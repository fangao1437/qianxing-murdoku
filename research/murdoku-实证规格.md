# Murdoku 实证规格（本工程的操作框架就是照它复刻的）

> 完整取证报告（480 行，含逐条"实证 / 文章说法 / 推断"标注与来源清单）在工作区根目录：
> `D:\新建文件夹\miHoYo Launcher\murdoku-复刻规格.md`
> 本文件是**与本工程直接相关**的收敛版，供实现/复核时快速查阅。

## 1. 棋盘

| 项 | 结论 |
|---|---|
| 规模 | **N×N 正方形**，N = 角色总数（含受害者），代码允许 3..24，线上出现 5/6/7/8/9/10/12/16，且 `suspects == gridSize` |
| 坐标换算 | `col = trunc((letter_xpos - grid_rx) / cellsize)`，`row = trunc((letter_ypos - grid_ry) / cellsize)`，`cellsize` 默认 150 |
| 房间 | 每格有 `room_code`；**墙 = 房间边界**（相邻 room_code 不同处画粗墙），同房间内部是细网格线 |
| 场景层 | 背景 → 房间底色/地板 → 逐格家具（`room_objects`，151 种对象）→ 格点装饰 → 门窗 |
| 渲染层级 | 地板 → 地毯 → 高亮 → 墙 → 家具 → 铅笔小字 → 放置大字母 → 悬停 → 长按进度环 |

## 2. 规则（官方 howToPlay）

1. `onePerRowCol`：每行每列**恰好**一人。
2. `occupiable`：只能放在"可站格"上（不能站在桌子、树等上面）。
3. `beside`：**上下左右四邻，且必须在同一区域（房间）**。
4. 目标：**凶手 = 与受害者单独共处一室的人**（该房间内只有他们两人）。
5. 无需猜测、保证唯一解、线索永远为真；"某人/有人"包含受害者；
   头像纯装饰（除线索明确提到服饰）；"旁边有个架子"可对多个架子成立。

**受害者与凶手怎么定**：受害者没有独立字段，前端取"符号为 V 的角色，否则取最后一个角色"；
`PROPERTIES.murderer` 存凶手索引（The Courtroom 实测 `murderer=5` → Fritz，与官方提示一致）。
→ 本工程要求你在关卡里**显式写** `victim` 与 `murderer`，别依赖顺序约定。

## 3. 线索体系

- 每个角色 1 条线索（可带副行），外加 0..3 条自定义全局线索，或最多 10 条"数字代码"全局线索。
- **线索文案是人工写的自然语言**，游戏本体不生成句子，只用多语言关键词表做高亮。
- 个人线索原子类型：`room / notRoom / orroom / beside(家具) / notbeside / on / onlyon /
  onlyBeside / with / withOnly / alone / alonewith / inCorner / cornerRoom / cornerGrid /
  notCorner / absRow / absCol / rowOffset / colOffset / compass / otherbeside /
  genderinroom / victim`。
- 全局线索数字代码（`clue_1..clue_10`）：没有空房间 / 恰好一个空房间 / 恰好一人在椅子上 /
  恰好一人在床上 / 一个或多个空房间 / 没人在水里 / 恰好一人在地毯上 / 恰好两个空房间 /
  恰好两人在椅子上 / 恰好三人在椅子上 / 没有嫌疑人与异性同房间。
- 关键词语义（权威）：`in front of` = 门窗直连的两格；`alone with` = 同区某人且无第三人；
  `own area` = 以该角色命名的区域；`wall` = 任何粗黑边（含外框）；
  `corner` = 两面墙相交处；`north/south/...` = 任意区域的上下左右格；`diagonal` = 45° 且不共行列。

→ 本工程把这些原子实现成了 **54 种 `M.clues` 类型**（见 `docs/关卡数据格式.md` 第 6 节）。

## 4. 交互模型（最容易做错的部分）

| 操作 | 行为 |
|---|---|
| 点头像卡 | 选中；已放置的卡片下沉 2px |
| **轻点格子** | 写/删**铅笔笔记**（小字，不占位） |
| **长按格子** | **放置**（大字母）并清空选中；目标格有人则替换 |
| 按住拖动 | 连续刷笔记 / 连续刷 X |
| 右键 | 切换该格 X |
| X 模式 | 标记"不可能"；放置后可选自动填同行同列 X |
| 橡皮擦 | 轻点清该格；**长按 1125ms 清空全盘**（带进度环倒计时） |
| 双指触屏 | **回滚到本次手势之前的棋盘快照** |
| Ctrl+Z / Ctrl+Y | 撤销 / 重做 |
| 长按头像卡 700ms | 给候选人画删除线（划掉） |
| 提交 | 未摆满时按钮显示 "(place all first)" 且无效 |
| 结算 | 全对 → "You've found the murderer! X killed Y"；有错 → "n of m correct" |
| 其他 | 计时器（每秒步进、每 10s 落盘）、Hint 分步提示、解答视频、打印（11in×8.5in 横版） |

**开屏教程 5 页**：①怎么破案 ②每行每列一人 ③beside 的含义 ④"长按才放置，轻点只留铅笔笔记" ⑤提交判题。

## 5. 页面布局

```
顶部工具条：Tools / X Mark / Clear / Undo / Submit / Options / How to Play / About
            / Print / Share / Restart / Reveal / Hint / Back to Puzzles
左侧面板（默认 340px）：头像卡 + 线索卡 + 图例（Note symbols / Suspects / Clues /
            General Clues / Victim / Murderer / CASE SOLVED / Solved in {time} /
            Placed at {cell} / click to select, hold on grid to place）
中央：棋盘 + R1..Rn / C1..Cn 坐标尺（默认仅在提示时显示）+ 房间名标签
右侧面板（默认 168px）
弹窗层 / 打印层 / 开场动画（Pop / Falling blocks / Flashlight sweep 三选一）
```

列表页（`/play/`）是关卡列表：难度筛选（Very Easy…Expert）、排序、隐藏已完成/未发布、
卡片显示 `{w}×{h} grid`、`{n} suspects`、进度状态；**信封卡**=未解锁关卡（每 7–12 秒随机抖动）。

## 6. 视觉/动效语义（本工程 `M.EFFECTS` 的命名来源）

`.mrd-stamp-btn`（印章按钮，按下位移 + 阴影）、`.mrdPortraitGroup/Child`（hover 放大 1.02 + 4px 蓝描边
`rgb(99,180,255)`）、`.portrait-name-bar`、`.clue-box-pop` / `.mrd-clue-in`（线索逐条 45ms 进场）、
`.mrdHoverGlow`、`.mrd-roomwall`（墙层淡入）、选中脉冲（1.12→1.03→1）、
撤销闪一下、提交按钮 nudge、破案金光 `.just-solved` / `.trophy-pulse`。

## 7. 数据端点（全部无鉴权，方便你对照真实关卡）

```
https://murdoku.com/play_puzzles/_puzzleCatalog.json      # 关卡目录
https://murdoku.com/play_puzzles/en/{id}.json             # 关卡全量数据
https://murdoku.com/play_puzzles/{lang}/{id}-{lang}.json  # 翻译补丁
```

## 8. 未能取到的部分（如实记录）

- DOM/JSX 具体结构（只能由 CSS 类名反推，元素归属为推断）。
- 长按阈值精确毫秒（只知道相邻常量：整盘擦除 1125ms、划掉 700ms、消失 600ms）。
- Arcade / Daily Run 的关卡生成算法全貌。
- `puzzle_version>=2` 的坐标对顺序（v1 已端到端证明为 (列,行)，v2 为强推断）。
