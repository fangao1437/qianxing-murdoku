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

## 规矩
- 从 `_wip` 毕业的条件：**跑通且能红能绿**（跑旧版会红 ⇒ 说明有方向 ✓）。
- **不许**把 `_wip` 里的失败计入"预存在红榜"（那是 `entry_smoke` 11 / `selftest` 4 的专属）。
