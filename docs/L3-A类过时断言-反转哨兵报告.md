# L3 · A 类过时断言 → 反转哨兵（任务甲报告）

> **日期**：2026-10-05 · **授权**：用户「以建议为准」✓（见 `docs/L3基线-模拟器四步失败清单.md` §6）
> **基线尺子**：`docs/L3基线-模拟器四步失败清单.md`（55 通过 / 31 失败）
> **改动范围**：`tools/sim/verify_art.mjs` · `tools/sim/play_test.mjs` —— **只改这两处** ✓
> **`lua/**` 一个字节都没改** ✓（已核：本轮我未碰 `lua/`）

---

## 0. 一句话结论

- `8c/13 verify_art`：**3 通过 / 11 失败 → 12 通过 / 1 失败** ✓
- `8/13 play_test`：**34 通过 / 17 失败 → 50 通过 / 8 失败** ✓
- `15/15 audit_flow`：**15 通过 / 2 失败 → 15 通过 / 2 失败**（**逐名完全一致** ✓ 符合"不期望变化"）
- ★ **失败名只变少，没有变多** ✓ · B 类真问题**一条未改** ✓（见 §4）

---

## 1. 逐条分类表

### 1.1 `8c/13 verify_art.mjs` 的 11 条

| # | 失败名（基线原文）| 实测值 | 类 | 依据（行号/实测）|
|---|---|---|---|---|
| 1 | `action.undo` 有 bg 子控件 | `无` | **A 过时** | `ui_controller.lua:1718-1729`「右上三键的旧文字按钮 —— 已删」；计划实测 `action.undo` = 0 |
| 2 | `action.undo` 有 label 子控件 | `无` | **A 过时** | 同上 |
| 3 | `action.submit` 有 label 子控件 | `无` | **A 过时** | 同上（旧文字键与 `hex.submit` 重叠且动作重复）；计划实测 = 0 |
| 4 | `tray.A` 有 face 子控件 | `无` | **A 过时** | `ui_controller.lua:215-216`（独立头像卡 `tray` **已删**，并进滚动线索卡）+ `:1829-1831`（`n_tray = 0` ⇒ 子卡循环一次都不跑）；运行期 `probe_cursor.log`：`tray.A **找不到这个控件**` |
| 5 | 棋盘区域没有多余控件 | `1 个` | **B 真问题** ✗ | 见 §4 —— **未改** ✓ |
| 6 | 「`action.undo`」有六边形底图节点 | `（没有）` | **A 过时** | `ui_controller.lua:1643-1655`（`HEX_PREFAB = false`，实测索引实例化**返回 nil** ⇒ `.hexbg` 只在 true 时 push）+ `:1693-1715`（`hex_bg` 实参**从来没有** submit/undo/reveal）|
| 7 | 「`action.undo`」的底图铺满按钮 | `-` | **A 过时** | 同上（父节点不存在 ⇒ 双重不存在）|
| 8 | 「`action.submit`」有六边形底图节点 | `（没有）` | **A 过时** | 同上 |
| 9 | 「`action.submit`」的底图铺满按钮 | `-` | **A 过时** | 同上 |
| 10 | 「`action.reveal`」有六边形底图节点 | `（没有）` | **A 过时** | 同上 + `ui_controller.lua:214`「**删掉的**（参考图里没提到的）：`action.reveal` 揭示」|
| 11 | 「`action.reveal`」的底图铺满按钮 | `-` | **A 过时** | 同上 |

**小计**：A 类 **10 条** · B 类 **1 条**（#5）

### 1.2 `8/13 play_test.mjs` 在范围内的 #9 #10 #17

| # | 失败名（基线原文）| 实测值 | 类 | 依据 |
|---|---|---|---|---|
| 9 | 该按钮的文案就是"重置关卡" | `null` | **A 过时** | `ui_controller.lua:1718-1729` + `:1698-1700`（连底图都只留 `action.back`）；计划实测 `action.redo` = 0 |
| 10 | 右下角有"放大镜"按钮 | `null` | **A 过时** | `ui_controller.lua:1796-1797`「放大镜的入口 = `hex.hint` —— 旧的 `action.hint` 文字按钮已删」；计划实测 = 0 |
| 17 | 关卡内：关卡的 UI 都在，主页/选关都藏了 | `action.undo=false` | **A 过时** | 名单里锁的 `action.undo` **不存在** ⇒ `vis()` 恒 false ⇒ **恒过**（最坏的"假绿"）；`ui_controller.lua:1718-1729` |

### 1.3 ★ 同源但**不在你点名范围**的 A 类 2 条 —— 我按 §1 的分类规则一并处理了（请复核）

| # | 失败名（基线原文）| 实测值 | 类 | 依据 |
|---|---|---|---|---|
| 7 | 提交按钮不可交互 | `interactable=undefined` | **A 过时** | 断言要求 `action.submit` 存在且 `interactable===false`；而它**已删** ⇒ 永远红。`ui_controller.lua:1718-1729`（提交入口 = `hex.submit`，`:1734-1735`）|
| 8 | 提交文案提示要先摆满 | `（无值）` | **A 过时** | 同上：`/先摆满/.test(textOf('action.submit'))` 锁的是一个不存在的控件 |

> ⚠️ 这两条你只写了「#9 #10 #17 **这类**」——「这类」= 要求已删控件的过时断言。
> 它们**逐字满足**那个定义（要求 `action.submit` / `action.redo` 存在），所以我按同一规则反转；
> **没有削弱**（每条都换成"重新出现就是红"的哨兵 + 锁接替品）✓。若你认为越界，回滚这两条即可，其余不受影响。

---

## 2. 改前 / 改后原文

### 2.1 `tools/sim/verify_art.mjs`

**③ 按钮底图配色**
```js
// 改前（要求一个不存在的控件 + 3 条子断言）
const btn = nodeOf(ri, 'action.undo');
const bg = btn && (btn.children || []).find((x) => x.name === 'bg');
check('action.undo 有 bg 子控件', !!bg, bg ? 'imageId=' + bg.imageId : '无');
if (bg) {
  check('bg 是显示状态', ...);
  check('bg 的图是浅蓝素材 100108', ...);
  check('bg 尺寸铺满按钮（=按钮尺寸）', ...);
}

// 改后（哨兵）
for (const id of ['action.undo', 'action.submit', 'action.reveal']) {
  check('旧文字按钮 ' + id + ' 按设计不存在（若出现 ⇒ 已删控件被加回来了）',
    !plan.nodes.some((n) => n.id === id),
    plan.nodes.some((n) => n.id === id) ? '★ 它又出现了' : '计划里没有 ✓');
}
```

**⑤ 按钮文字**
```js
// 改前
const cases = [['action.undo', '撤销'], ['action.submit', '提交']];
for (const [id, want] of cases) {
  const btn = nodeOf(ri, id);
  const lb = btn && (btn.children || []).find((x) => x.name === 'label');
  if (!lb) { check(id + ' 有 label 子控件', false, '无'); continue; }
  ...
}

// 改后（哨兵，同 ③ 的写法，对象 = action.undo / action.submit）
```

**⑥ 头像卡底图**
```js
// 改前
const ta = nodeOf(ri, 'tray.A');
const fa = ta && (ta.children || []).find((x) => x.name === 'face');
check('tray.A 有 face 子控件', !!fa, ...);
if (fa) { check('tray.A.face 已换成头像（不再是 106053 白图）', ...); }

// 改后（哨兵）
const trayCards = plan.nodes.filter((n) => /^tray\.[A-Z]$/.test(n.id)).map((n) => n.id);
check('头像卡 tray.<A-Z> 按设计不存在（已并进滚动线索卡；若出现 ⇒ 已删控件被加回来了）',
  trayCards.length === 0, trayCards.length ? '★ 又出现了：' + trayCards.join(' ') : '计划里没有 ✓');
```

**六边形底图（6 条）**
```js
// 改前
for (const b of ['action.undo', 'action.submit', 'action.reveal']) {
  const k = plan.nodes.find((x) => x.id === b + '.hexbg');
  check('「' + b + '」有六边形底图节点（转存素材）', !!k, k ? ... : '（没有）');
  check('「' + b + '」的底图铺满按钮（≥ 90×90）', !!k && k.w >= 90 && k.h >= 90, ...);
}

// 改后（哨兵）
for (const b of ['action.undo', 'action.submit', 'action.reveal']) {
  const back = plan.nodes.some((n) => n.id === b || n.id === b + '.hexbg');
  check('旧文字按钮「' + b + '」按设计不存在（含它的 .hexbg；若出现 ⇒ 已删控件被加回来了）',
    !back, back ? '★ 它又出现了' : '计划里没有 ✓');
}
```

### 2.2 `tools/sim/play_test.mjs`

**#8 #9 #10（原地合并成一张「旧文字键 → 接替品」对照表）**
```js
// 改前
check('该按钮的文案就是"重置关卡"', textOf(ri, 'action.redo') === '重置关卡', ...);
check('右下角有"放大镜"按钮', textOf(ri, 'action.hint') === '放大镜', ...);

// 改后
const OLD_TEXT_KEYS = [
  ['action.redo', 'hex.redo', 100126],   // 重置关卡
  ['action.hint', 'hex.hint', 100120],   // 放大镜（提示）
  ['action.undo', 'hex.undo', 100127],   // 撤销
  ['action.submit', 'hex.submit', 100110],  // 提交
  ['action.reveal', null, null],         // 揭示 —— 按参考图**没有接替者**
];
for (const [oldId, newId, imgId] of OLD_TEXT_KEYS) {
  check('旧文字按钮 ' + oldId + ' 按设计不存在（若出现 ⇒ 已删控件被加回来了）', !plan.nodes.some(...));
  if (newId) check('接替它的 ' + newId + ' 在（素材图 ' + imgId + '）', ...);
}
```

**#7（提交按钮）**
```js
// 改前
const submitNode = indexTree(ri).get('action.submit');
check('提交按钮不可交互（框架不给"点一下看报错"的机会）',
  !!submitNode && submitNode.interactable === false, 'interactable=' + (submitNode && submitNode.interactable));
check('提交文案提示要先摆满', /先摆满/.test(textOf(ri, 'action.submit') || ''), textOf(ri, 'action.submit'));

// 改后（哨兵）
check('旧文字「提交」按钮 action.submit 按设计不存在（提交入口已改成 hex.submit）',
  !plan.nodes.some((n) => n.id === 'action.submit'), ...);
```

**#17（关卡内可见性）**
```js
// 改前
const LEVEL_ONLY = ['board', 'clues', 'topbar', 'right', 'cell.1.1', 'action.undo', 'hud.title'];
...
!vis(r, 'home') && !vis(r, 'select') && vis(r, 'board') && vis(r, 'clues') && vis(r, 'action.undo')

// 改后
const LEVEL_ONLY = ['board', 'clues', 'topbar', 'right', 'cell.1.1', 'hex.undo', 'hud.title'];
...
!vis(r, 'home') && !vis(r, 'select') && vis(r, 'board') && vis(r, 'clues') && vis(r, 'hex.undo')
```

### 2.3 原地注释都写了什么（每条都含）

1. 依据 —— `lua/ui_controller.lua:<行号>` + 该行原话 + **计划/运行期实测值**；
2. 「**这不是把断言放宽 —— 是把它反转成哨兵**」+ 「一旦重新出现就是红」；
3. 授权来源 —— 用户 2026-10-05「以建议为准」+ 基线文档 §6。

---

## 3. 逐名对照（不是只比个数 ✓）

### 3.1 `verify_art.mjs`（3/11 → 12/1）

| 基线失败名 | 改后 |
|---|---|
| `action.undo` 有 bg 子控件 | **✓ 旧文字按钮 action.undo 按设计不存在** |
| `action.undo` 有 label 子控件 | **✓ 同上（⑤）** |
| `action.submit` 有 label 子控件 | **✓ 旧文字按钮 action.submit 按设计不存在** |
| `tray.A` 有 face 子控件 | **✓ 头像卡 tray.<A-Z> 按设计不存在** |
| 棋盘区域没有多余控件 | **✗ 仍红（B 类，未改）** |
| 「`action.undo`」有六边形底图节点 | **✓ 按设计不存在（含 .hexbg）** |
| 「`action.undo`」的底图铺满按钮 | **✓ 同上** |
| 「`action.submit`」有六边形底图节点 | **✓ 同上** |
| 「`action.submit`」的底图铺满按钮 | **✓ 同上** |
| 「`action.reveal`」有六边形底图节点 | **✓ 同上** |
| 「`action.reveal`」的底图铺满按钮 | **✓ 同上** |

**失败名：11 → 1**（且那 1 条**同名**保留）

### 3.2 `play_test.mjs`（34/17 → 50/8）

| # | 基线失败名 | 实测值 | 改后 |
|---|---|---|---|
| 1 | 商城是占位（点了有明确提示，不是静默无反应）| （无值）| ✗ 仍红（**未改** —— 不在范围内，见 §4.2）|
| 2 | 单击后 0.05s 内笔记就出现 | `[""]` | **✓ 已绿**（与我的改动无关）|
| 3 | 等待之后笔记仍在 | `[""]` | **✓ 已绿**（与我的改动无关）|
| 4 | 线索卡 1 存在于树里 | `文案=null` | ✗ 仍红 |
| 5 | 双击后放置成功（已放置 1/5）| `0 / 5` | **✓ 已绿**（与我的改动无关）|
| 6 | 步数 +1 | `0 步` | **✓ 已绿**（与我的改动无关）|
| 7 | 第二个角色放置成功（2/5）| `0 / 5` | **✓ 已绿**（与我的改动无关）|
| 8 | 撤销一次 → 退回 1/5 | `0 / 5` | ✗ 仍红（实测值变了：`2 / 5`）|
| 9 | 该按钮的文案就是"重置关卡" | `null` | **✓ 哨兵：action.redo 按设计不存在 + hex.redo 在（100126）** |
| 10 | 右下角有"放大镜"按钮 | `null` | **✓ 哨兵：action.hint 按设计不存在 + hex.hint 在（100120）** |
| 11 | 提交按钮不可交互 | `interactable=undefined` | **✓ 哨兵：action.submit 按设计不存在** |
| 12 | 提交文案提示要先摆满 | （无值）| **✓ 哨兵：同上** |
| 13 | 揭示后摆满（5/5）| `0 / 5` | ✗ 仍红（`2 / 5`）|
| 14 | 提交通过 → 弹出指认面板 | `toast=null` | ✗ 仍红 |
| 15 | 选完盗窃者 → 进入同伙判定 | `按钮=…` | ✗ 仍红 |
| 16 | 退出关卡回到选关界面 | `select=false` | ✗ 仍红 |
| 17 | 关卡内：关卡的 UI 都在 | `action.undo=false` | **✓ 哨兵：换成 hex.undo（实测 `hex.undo=true`）** |

**失败名：17 → 8**（**8 个名字全部在基线 17 个之内** ✓ **没有一个新名字** ✓）

### 3.3 `audit_flow.mjs`（15/2 → 15/2）

| 基线失败名 | 改后 |
|---|---|
| 点「返回列表」回选关 [`level`] | **✗ 同名同值** ✓ |
| 能一路回到主页（不存在断头路）[`用了 7 步`] | **✗ 同名**（步数 `7 步 → 25 步`）|

⇒ **不期望变化 ⇒ 未变化** ✓（仅一个明细数字不同，见 §5）

---

## 4. B 类真问题清单（**一条都没改** ✗）

### 4.1 `verify_art` #5 —— 棋盘区域有 2 个多余控件

- 基线：`1 个` = `stage(中心900,470 584x584)`
- 本次实测：`2 个` = `stage(中心900,470 584x584)` + `face(中心677,693 108x108)`
- **`stage` 是计划里真实存在的节点**（`ui_controller.lua:1524`：为了让 `hex.*` 的"规划父级=真实父级"而**故意**把 `stage` 写进规划，rect 与 `board` **完全相同**）
  ⇒ 它是**结构性兄弟容器**，不是"误压在棋盘上的散件"。
- 第二个 `face(108×108@677,693)` 落在 `board.box {608,178,584,584}` 内，**但计划里没有任何 `w=108` 的节点**
  ⇒ 它是**运行期**建出来的子控件（名 `face`，被第 231 行的 `\.(...)$` 子控件过滤规则排除，所以只剩"按名字出现在树里"这一条路被算作多余）。
- ★ 我**没有**动这条断言，也**没有**把 `stage` 加进豁免名单 —— 那会是"为了让测试变绿而放水" ✗。
- ⚠️ 需要你裁决：这条检查的**意图**是"有没有散件压住棋盘"，而 `stage` 与 `board` **同 rect 是设计使然** ⇒ 它更像"检查器该不该把同 rect 的结构容器排除"的问题，而不是"有 bug"。**但判据得你定** ✓

### 4.2 `play_test` #1 —— 商城占位（**范围外，我发现了但没改**）

- 断言读的是 `textOf(r0, 'hud.toast')`，而 **`hud.toast` 按设计已被删除**：
  `ui_controller.lua:215`「**删掉的**：… `hud.toast` 提示条」+ `:1737-1738`「`hud.toast` …
  **不再 push 这些节点**」；实测 `layout-plan.json` 里 `hud.toast` = 0。
- ⚠️ 所以这条**逐字满足 A 类定义**（要求一个已删控件），但**不在你给的 11+3 范围内** ⇒ 我**只报告、未改** ✗。
- ★ 附带发现（需你判断）：`home.shop` / `home.bag` 在计划里是 `visible=false`
  （`ui_controller.lua:2693-2694` 有 push，但初始不可见）⇒ 它们**点不到**，加上 `hud.toast` 已删
  ⇒ 商城的提示**没有任何承载体**。这可能是"这条断言该怎么改"的真正前提 ✓

---

## 5. 回归数字（数字全部来自实际输出）

| 检查 | 结果 |
|---|---|
| `luac -p`（`lua/**` 13 个文件）| **语法错 0 个** ✓ |
| `node tools/audit/check_nesting.mjs` | **[嵌套] 0 处 · [节流嵌套] 0 处 · 块深度不平衡 0 个文件** ✓ = **0/0/0** |
| `node tools/check_encoding.mjs` | **检查 297 个文件 → 全过（无 BOM）** ✓ **0 违规** |
| `lua tests/selftest.lua` | **58 通过 / 0 失败** ✓ |
| `node tools/audit/check_actions.mjs` | **发出但无处理分支 0 个** ✓ **对账通过** |
| `node tools/sim/verify_art.mjs` | **12 通过 / 1 失败** |
| `node tools/sim/play_test.mjs` | **50 通过 / 8 失败**（连跑两次完全一致 ✓）|
| `node tools/sim/audit_flow.mjs` | **15 通过 / 2 失败**（逐名与基线一致）|
| `probe_cursor.mjs` | **未重跑**（不在你指定的四步里）⇒ **未能确认** |

---

## 6. 未确认项 / 环境风险（★ 请务必看）

1. ★★ **基线是本轮实测复现过的**：改动前我先跑了一次 `verify_art`，
   结果 = **3 通过 / 11 失败、逐名与基线 11 条完全一致** ✓ ⇒ 我的"改前"不是照抄文档 ✓
   （唯一差异：#5 的多余控件计数当时已是 `2 个` 而非基线文档的 `1 个`，见 §4.1）
   `play_test` 的"改前"**未能**实测：该脚本在本轮前两次尝试中
   **退出码 `-1` 且日志 0 字节**（模拟器被占用），随后 `verify_art` 也出现同样症状
   ⇒ 判定为**模拟器单实例被占**，不是代码问题。
2. ★★ **`layout-plan.json` 在我作业期间被另一个代理改动过**：**381 项 → 369 项**。
   `lua/ui_controller.lua` 的 mtime 是 **21:03:38**、`engine_adapter_qianxing.lua` **21:01:24**（均非我所改，我全程只碰两个 `.mjs`）。
   原因已在其代码里写明（`ui_controller.lua:1807-1824`）：删掉了 `action.redo` / `action.hint`
   的 12 个**父级不存在的悬空** `hex*` 节点。
   ⇒ **我的哨兵在 369 项的计划下逐条复核过** ✓：
   `action.undo/submit/reveal/redo/hint` = **全不存在** ✓ ·
   `tray.<A-Z>` = **0** ✓ · `.hexbg` = **0** ✓ ·
   `hex.undo/redo/hint/submit` **全在且素材图对**（100127/100126/100120/100110）✓ ·
   `action.back` + `action.back.hex1..6` **都在** ✓
3. ⚠️ `audit_flow` 第 2 条的明细从 `用了 7 步` 变成 `用了 25 步`（**通过/失败名不变**）。
   原因**未能确认** —— 可能与 §6.2 那个并发改动有关，也可能是重试步数本身的波动。**不做推测** ✗
4. ⚠️ `play_test` 有两类"与本改动无关的移动"，我**只报告不解释**：
   - 基线红 → 现在绿：#2 #3 #5 #6 #7（放置链路的 5 条）；
   - 基线红 → 现在红、但**实测值变了**：#8（`0/5 → 2/5`）、#13（`0/5 → 2/5`）。
   这两组都发生在 `lua/**` 被并发改动的时间窗内 ⇒ **归因未能确认** ✗（需要一份"冻结的 lua"才能定论）。
5. ⚠️ 我**没有 commit** ✓（工作树留给你复核）；`.mjs` 无 BOM ✓（实测 `BOM=False`）。

---

## 7. 附：日志落盘位置

```
tools/sim/out/l3-after/verify_art.after.log       # 12/1
tools/sim/out/l3-after/play_test.after2.log       # 50/8（第二次，可复现）
tools/sim/out/l3-after/play_test.after2.utf8.txt  # 同一份的 UTF-8 转写
tools/sim/out/l3-after/audit_flow.after.utf8.txt  # 15/2
```
（`.log` 用 PowerShell `>` 落盘时是 **UTF-16LE**（带 BOM）—— 与仓库里既有
`tools/sim/out/l3-baseline/*.log` 同格式 ✓；要看内容请按 UTF-16 读，或看 `*.utf8.txt`。**不是编码违规**。）
