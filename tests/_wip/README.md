# tests/_wip —— **未完成/不可信**的测试（不计入套件）

放在这里的测试**不许**算作回归防线，也**不许**当作证据用。

## perframe_throttle.lua（2026-10-05 由子代理生成，**已隔离**）

**为什么隔离**：它第 1 条断言就失败于
`attempt to call a nil value (upvalue 'oar')` —— 是**测试自己的假引擎写错了** ✗，
所以整轮结果（2 过 5 败）**不可信** ✗。

**它想验证的**（内容有价值，等修好再用）：
1. 关卡内 `cell.*` / `selbar` 的"每帧压住"到底还在不在（代码注释 L1522-1525 声称**必须每帧**）；
2. `apply_ruler_layout` 每次 render 都重复打印（内容没变就没新信息）；
3. 不许有运行时报错。

**它测出来的东西（未经确认）**：`cell.1.1 SetVisible 0 次 / 60 帧`、`selbar SetVisible 0 次` ——
与"注释声称每帧压住"矛盾 ⚠️。这**可能是**：
(a) 代码真的被节流了（那注释就过时了）；
(b) 或者测试的假引擎没走到那条路（因为第 1 条已经证明假引擎有问题 ✗）。
⇒ **未能确认**，修好假引擎后重测才能定案。

## probe_accuse_flow.lua（2026-10-05，本次「补 accuse_thief + 去掉分享」的证据，**可信**）

**为什么可信**：它**能红能绿** —— 对**改前**的 `ui_controller.lua` 跑 = **5 通过 / 11 失败**（exit 1），
对改后的跑 = **16 通过 / 0 失败**（exit 0）。跑法：

```
lua tests/_wip/probe_accuse_flow.lua              # 用本仓库 lua/
lua tests/_wip/probe_accuse_flow.lua <别的root>   # 对旧版跑（要那 root 下有 lua/ 一套）
```

它覆盖：`submit → ✓confirm_yes → accuse_thief(D) → accuse_pick_accomplice(C) → 破案(SOLVED)` 的真实通路、
第二阶段把被指认者排除、结算计划里没有 `modal.share` 节点（且 `modal.again/next` 还在 —— 防"空集通过"）、
以及 `reveal` 不再弹出"那同伙是谁？"。

⚠️ 它仍然**不算回归防线**（`_wip` 的规矩不变，见下）；它是**这一次改动的证据**。
要长期留，请在 `lua/` 稳定后把它按同样断言搬进 `tests/` 根目录的套件里。

## probe_cell_click_chain.lua（2026-10-05，本次「点格子没反应」三段切开的证据，**能红能绿**）

**跑法**：`lua tests/_wip/probe_cell_click_chain.lua`（当前 = **28 通过 / 0 失败**，exit 0 ✓）
**不跑模拟器** ✓ **不改 `lua/**`** ✓ —— A 段用假引擎（假控件树 + 假 Enum）把真适配器跑起来。

它切开三段并逐段给实测值：C 逻辑层（双击间隔 0 / 0.1s / 0.4s）· B 路由层（phase 各档、
`r/c=nil`、`_suppress_click`）· A 事件层（`bind_input` 到底绑没绑 + 派发的字段与类型）·
端到端复刻 `probe_cursor.mjs` 的动作序列。

**为什么说它能红**（三条负对照，任一失效即红 ✓）：
`A3` 抽掉 `Enum` ⇒ 必须一个都绑不上 · `D2a` 事件表换成兜底 ⇒ click 档必须仍拿到 number 的 `r/c`
（这条就是提交 `6f04c64` 的定向判据；**未对旧提交实跑** ✗ —— 本机没有 git ✓）·
`D2b` 反事实：down/up 档会崩在 `murdoku_core.lua:1917`。

⚠️ 仍然**不算回归防线**（`_wip` 的规矩不变）；结论与证据链见
[docs/点格子没反应-三段切开结论.md](../../docs/点格子没反应-三段切开结论.md) ✓

## render_cost_faithful.lua ／ perframe_engine_calls_faithful.lua（2026-10-13，**忠实树** ✓）

**为什么有它们 ✗**：原来的 `render_cost.lua` / `perframe_engine_calls.lua` 用的是**手搭假树**，
而那棵树**漏了真存档里确实存在**的 8 个边控件 ——
`wall.up/down/left/right`、`door.up/down/left/right`（父控件全部 ＝ `content`）：

```
node tools/gil/list_names.mjs 347.gil wall     → 8 个，父 = content
node tools/gil/list_names.mjs 347.gil door     → 8 个，父 = content
```

⇒ 每一次 `sub(cell,"wall.up")` 都**注定未命中** ⇒ 凭空造出 **840 笔 `GetChild` / 一次 render** ✗
⇒ 而 v213 有"按代未命中记忆"、v192 没有 ⇒ **那 840 笔全记在 v192 头上** ⇒
量出一个**不存在的** "972 → 132（−86%）" ✗✓

**这两个文件做的两件事** ✓：
1. 给每个格子的 `content` **补上**那 8 个边控件（与 `347.gil` 对账）；
2. **去掉**假树**反向假造**的 10 个控件（`ruler.c.1..5` / `ruler.r.1..5` —— 存档里只有 `ruler` 与 `tpl.ruler`，没有这些标签）。

**补忠实之后的实测（2026-10-13）** ✓：

| 指标 | v192 | v213 |
|---|---|---|
| 一次稳态 render | **111** | **111** |
| └ `GetChild` / `GetSizeDelta` | **0 / 0** | **0 / 0** |
| 换代后第一趟（冷） | 29,786 | 25,947 |
| 每帧（60 帧窗） | 100.5 | 42.0 |
| 每帧（300 帧窗） | 40.3 | 28.4 |
| `GetChild`/帧 | 1.00 | 1.00 |

⇒ **差额全在 `GetChildren`（整树遍历）**；`_sub_miss` 在 wall/door 这条路上**买不到可测收益** ✓

**跑法** ✓（产物路径请用 **ASCII 路径** ✗ —— Lua 解释器在中文路径下拿不到参数）：

```
lua tests/_wip/render_cost_faithful.lua          <产物> [cold|switch]
lua tests/_wip/perframe_engine_calls_faithful.lua <产物> [帧数]   # 建议 60 与 300 各跑一次
```

**产出可复现的产物身份** ✓：v192 sha `32DFC2AF…`、v213 sha `4054178B6A6EBF63`
（两个产物各含 4 个"孤立 CR 字节"⇒ PowerShell 行号比真实行号**多至多 4** ✗）

★★★ **新增第 ④ 条规矩** ✗✓：**探针的树必须与存档对账** ——
"探针包了产线遍历的那棵树" ≠ "**那棵树是真的**" ✓✓
依据与全量证据：`-project` 仓 **`审计-性能-v192对213.md`** §0 更正声明（含 `347.gil` 实证与更正前后对照）。

⚠️ 它们**仍然不算回归防线**（`_wip` 的规矩不变）：假树虽已与存档对齐，但**仍是手搭的替身**
（349 个控件 vs 存档 293 条记录）⇒ 只有"两版之间怎么变"可比，**绝对量级不是设备真值**，更不能当毫秒 ✓

## 规矩
- 从 `_wip` 毕业的条件：**跑通且能红能绿**（跑旧版会红 ⇒ 说明有方向 ✓）。
- **不许**把 `_wip` 里的失败计入"预存在红榜"（那是 `entry_smoke` 11 / `selftest` 4 的专属）。
