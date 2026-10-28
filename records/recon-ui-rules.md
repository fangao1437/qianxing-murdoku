# Recon A：棋盘格动作的 UI 层调用点与反馈通路

> 只读侦察报告（**未修改任何 `.lua`**）。审计对象：`lua/ui_controller.lua` / `lua/entry_client_script.lua` /
> `lua/main.lua` / `lua/engine_adapter_qianxing.lua`（交叉验证 `dist/client_script.lua`，生成物）＋
> 复核 `lua/murdoku_core.lua` 的**在途改动**。

---

## ⚠️ 0. 并发改动警告（先读这一段）

侦察期间 **`murdoku_core.lua` 与 `ui_controller.lua` 都在被同时修改**（Lead 正在落地三条规则）。
本报告的**行号是下列快照时刻**，随时可能失效：

| 文件 | 快照大小 | 最后写入 | 本轮内是否变动 |
|---|---|---|---|
| `lua/murdoku_core.lua` | 122 168 B（≈2 950 行） | 05:45:26 | **是**（110 675 → 122 168，持续增长） |
| `lua/ui_controller.lua` | 569 883 B | 05:45:32 | **是**（568 714 → 569 883，`_refuse` 之后整体下移） |
| `lua/engine_adapter_qianxing.lua` | 345 656 B | 05:07:20 | 否（**行号稳定可信**） |
| `lua/main.lua` | 152 302 B | 05:07:20 | 否（**行号稳定可信**） |
| `lua/entry_client_script.lua` | 64 182 B | 05:23:57 | 否（**行号稳定可信**） |

**⇒ 引用方式：优先「函数名 + 代码特征」，行号只作定位起点。**
若行号对不上，用文中的**代码片段**去 grep（本篇已给足锚点）。

**已知漂移规律**：`_refuse`（`ui_controller.lua:806`）与 `M.EFFECTS`（`:258`）之前的部分未动；
`_refuse` **之后**的引用整体下移，`build_layout` 内部再下移一次（两批插入）。

---

## 1. 两个主问题的答案

### Q1：拒绝消息挂在哪？

**`Controller:_refuse(r, c, why)`，`lua/ui_controller.lua:806-824` —— 全项目唯一的拒绝出口。**

| 行 | 内容 |
|---|---|
| `806` | `function Controller:_refuse(r, c, why)` |
| **`807`** | **`if why == nil then return end`** ← **静默闸门：没有原因串 = 一个字都不打** |
| `808-811` | 按 `why` 文本去重，**同一句原因最多打 3 次**（`_refuse_seen`） |
| `812-823` | `print("[murdoku] 点 (第R行 第C列) 没生效：<why> 当前工具=<mode> 已选=<selected>（同类提示最多打 3 次）")` |

**四个调用点（全部在 `ui_controller.lua`，全仓 grep 无第五处）**：

| 行 | 所在函数（定义行） | 场景 |
|---|---|---|
| `854` | `flush_pending_note`（`842`） | 键盘 Space 落笔记被拒（**仅键盘可达**，见 §5.3） |
| `919` | `do_place`（`859`） | 长按 / 键盘 F 落子被拒 |
| `958` | `do_pre_place`（`929`） | 双击预放置被拒 |
| `1163` | `on_cell_click`（`1044`） | 单击（笔记 / ✗ / 拿起）被拒 |

⇒ **加新规则的提示不必动 `_refuse`**：只要 core 那端 `return false, "原因串"`，并且**中间包装把第二个值透传上来**。
问题恰恰出在中间包装 —— 见 §2。

**现有拒绝原因串（措辞参考，避免重复/冲突）**：`"越界"`、`"这个格子站不了人"`、`"先点一个头像"`、
`"这格已经有人了"`、`"先选一个人再打草稿"`、`"这个人已正式放置，不能再打笔记"`、
`"这格是障碍物，站不了人，也不能打笔记"`（本轮新增）。

### Q2：notes / ✗ 互斥要保持哪个绘制函数一致？

**`Controller:build_layout`（`ui_controller.lua:2124`）里的格子循环 `push({...})`，两个字段：**

| 字段 | 行 | 值 |
|---|---|---|
| **`notes`** | **`ui_controller.lua:3210`** | `notes = _note_val or false,`（`_note_val` 在循环顶部算，走 `mark_list_of` `446-460`，空集合 → `nil`） |
| **`x_mark`** | **`ui_controller.lua:3266`** | `x_mark = cd.x,`（`cd.x` 来自 `Core:view()` 的 `x = self.x_marks[r][c] == true`） |

**适配器侧两条渲染分支彼此完全不知道对方存在**（`engine_adapter_qianxing.lua`，**行号稳定**）：

```
key == "notes"  : 4635-4743   sub(id,"note") → c.text = txt; SetVisible(txt ~= "")   (:4669)
key == "x_mark" : 4744-4747   sub(id,"x")    → SetVisible(value and true or false)  (:4746)
```

`notes` 非空时还会 `SetActive(true)` + `SetAsLastSibling()`（`4670-4672`），把字母提到最上层。

**⇒ 绘制层没有任何互斥保护：数据层两个都为真 ⇒ 字母压在 ✗ 上同时显示。
互斥只能在核心层保证；`3210` 与 `3266` 必须保持「只搬运、不判断」。**
一旦有人在这两行加判断（如 `x_mark = cd.x and not _note_val`），就是**第二个真源** ——
本项目反复栽过的"同一概念两处实现必然漂移"（`ui_controller.lua` 的 `_on_grid_item_click` 附近有明确警告：
「拿派生值反过来当判据 = 把因果倒过来」）。

**另注意**：`build_layout` **优先读 `core.notes[r][c]`，不用 `cd.notes`**（`_note_val = mark_list_of(...)` 那几行）：

```lua
_note_val = mark_list_of((self.core and self.core.notes and self.core.notes[r]
  and self.core.notes[r][c]) or cd.notes, vm, _resolve)
```

`self.notes[r][c]` 恒为表 ⇒ **`cd.notes`（`Core:view()` 产出的那份）永远走不到**。
⇒ **任何"在 `Core:view()` 里过滤笔记"的做法对棋盘格都无效**，必须改在 `core.notes` 表本身或这两行上。

---

## 2. 在途实现：快照 @ 05:45

### 2.1 已落地并被本轮侦察确认修好的三处

这些点**一边被写一边被修**，记录在此以免 Lead 重复劳动：

| 编号 | 原症状 | 现状（已修） |
|---|---|---|
| **G1** | `Core:tap_cell` 只修了 `MODE_NOTE` 分支，**place 模式分支仍 `, nil`** ⇒ 规则 B 的拒绝在玩家最常走的路上静默 | 两条路径现在**都**是 `return toggle_note(self, r, c, self.selected)`，**原因串双向透传** ✅ |
| **G4** | `Core:undo` 的 `place` 分支仍是旧 inline 循环，**只还原 `auto.x`、不还原 `auto.x_notes`** ⇒ 规则 X 擦掉的笔记撤销后永久丢失（与注释「交给 `revert_auto` 在撤销/拿起时还原」自相矛盾） | 现在调用 `revert_auto(self, action.auto)` ✅ |
| **G5** | `undo`/`redo` 的 `note` 分支**从不读 `was_x`** ⇒ 在 ✗ 上打笔记后撤销，✗ 永久丢失，且撤销/重做不再互逆 | `undo` 补 `if action.was_x then self.x_marks[...] = true end`；`redo` 对称 ✅ |

### 2.2 🔴 仍开放的两处（截至快照）

#### G2 —— `hold_cell` / `pre_place` 仍把 `do_place` 的原因写死成 `nil`

```lua
-- Core:hold_cell 尾部
local ok = do_place(self, r, c, who, true, { clear_notes = true })
...
return ok, nil          -- ❌ do_place 的第二个返回值被丢弃
-- Core:pre_place 尾部
local ok = do_place(self, r, c, self.selected, true, { clear_notes = false })
...
return ok, nil          -- ❌ 同上
```

⇒ **R1（同行/同列不能再放人）若只改 `do_place`，玩家得到的是"长按毫无反应"，日志一个字都没有。**
修法：`local ok, why = do_place(...)` → `return ok, why`。
（`ui_controller.lua:872` / `936` 已经在收 `ok, why`，`919` / `958` 已经在调 `_refuse` —— **UI 侧无需改动**。）

#### G3 —— `do_place` 自身的拒绝仍不带原因

```lua
-- local function do_place(...)，函数开头
if self.blocked[cell_key(r, c)] then return false end     -- ❌ 无原因
local prev = self.grid[r][c]
if prev == id then return false end                       -- ❌ 无原因
```

R1 的检查要加在这两行附近，**必须写成 `return false, "……"`**，否则重演 G2 的静默。

### 2.3 R1（同行/同列不能再放人）—— **尚未落地**

截至快照，`do_place` 头顶只有 `blocked` 与 `prev == id` 两道门。落地时必须同时处理五件事：

**（a）检查位置与判据**
插在 `if prev == id then return false end` 之后、`if prev then` 之前。
用 `self:rules().one_per_row` / `.one_per_col` 门控（`Core:rules()`，默认 `~= false` 即**开**）；
用现成的 `self.row_count[r]` / `self.col_count[c]` 判，**不要遍历 `grid`**。

**（b）必须给原因串，并透传两处包装** → 即 §2.2 的 G2 + G3。

**（c）`record = false` 的调用必须跳过 R1**
`decode_state` / `undo` / `redo` / `hint` 都用 `do_place(..., false)` 重放。
⇒ 若无条件执行 R1，**旧存档 / 旧分享码里本就同行的盘面会被拒绝重放 ⇒ 读档静默丢子**。
⇒ 检查必须写成 `if record then ... end`（与同函数里 `push_history` 的条件一致），或新增 `opts.skip_rules`。

**（d）⚠️ 执行顺序陷阱（最危险，会导致角色凭空消失）**
`Core:hold_cell` / `Core:pre_place` 都是**先** `move_piece_if_needed(...)`（内部 `do_clear` 掉该角色**原来的位置**），
**再** `do_place(...)`。⇒ 若 `do_place` 因 R1 拒绝，角色**已经离开旧格且没落到新格** = 人没了。
两种解法：
- **推荐**：把 R1 检查**前置到 `move_piece_if_needed` 之前**，并显式放行「目标格同行/同列上唯一的占用者就是 `self.selected` 本人」的情况（那是合法挪位）。
- 或者：拒绝时用 `move_from`（`move_piece_if_needed` 已返回它；`Core:hold_cell` 现有 `if ok and move_from ~= nil` 就是给撤销用的）**回滚**。

**（e）`rules.one_per_row = false` 的关卡必须放行**
`tests/selftest.lua:342-356` 的 `probe` 关卡显式写 `rules = { one_per_row = false, one_per_col = true, ... }`（`:344`），
随后 `:353` 放 P 于 (1,1)、`:354` 放 Q 于 **(1,2) —— 同一行** ⇒ 不做规则门控，这条**当场红**。

### 2.4 R2（规则 X）—— 已落地，可逆性缺口已补（见 §2.1 G4/G5）

绘制层**不用改**（`3210` / `3266` 只搬运）。
⚠️ 唯一仍值得核对：`Core:undo` 的 **`x` 分支**只翻 ✗、不还原被 `toggle_x` 擦掉的笔记
（`toggle_x` 里 `if self.x_marks[r][c] then self.notes[r][c] = {} end`，但历史只压了 `{kind="x", r, c}`）。
这是**旧代码**，不是本轮引入；若要求「互斥完全可逆」，这里也得补 `had` 快照（与 `was_x` 同一形状）。

### 2.5 R3（规则 B）—— 已落地

- 拒绝串已给出：`"这格是障碍物，站不了人，也不能打笔记"`（`Core:toggle_note` 内 `if self.blocked[cell_key(r, c)]`）。
- 透传已补（G1 已修）✅。
- **`Core:toggle_x` 保持不加门控**（✗ 仍可打在障碍格）—— 与其注释一致，符合「✗ 那一半仍然开着」的口径 ✅。
- **存档/分享码不变量已补**：`Core:serialize` 写出前 `if x or blocked then note_ids = {} end`；
  `Core:decode_state` 用 `note_ok = not blocked` 挡外部输入 ✅。
- ⚠️ **注释仍需清理**：`Core:toggle_note` 顶部那段「去掉 `blocked` 门控 / 正是那种格子最需要能打笔记」
  仍以结论语气写着（其下已补「2026-10-20 用户改主意」的说明，但旧段落容易被下一个人当依据回滚）；
  `Core:tap_cell` 顶部同理（已补规则 B 注记）。

---

## 3. 核心方法调用点全表（生产代码）

> `ui_controller.lua` 行号为本轮快照；`murdoku_core.lua` 只给函数名（易变）。

| 方法 | 调用点 | 备注 |
|---|---|---|
| `tap_cell` | `ui_controller.lua:1110` | `on_cell_click` 主路径，**唯一带 `_refuse` 的 tap 点** |
| | `ui_controller.lua:848` | `flush_pending_note`（**仅键盘 Space 可达**，见 §5.3） |
| | `main.lua:2217` | `Murdoku.on_signal` 的 `SYNC_STATE`，**两个返回值都丢弃** |
| `hold_cell` | `ui_controller.lua:872` | `Controller:do_place` 内（长按 / 键盘 F / 双击放置共用） |
| | `ui_controller.lua:1465`→`reveal` 分支 | 逐人放答案，返回值丢弃（定位：`on_input` 里 `a == "reveal"`） |
| `pre_place` | `ui_controller.lua:936` | `Controller:do_pre_place` 内（双击 = 预放置） |
| `toggle_x` | `ui_controller.lua:1371` | `on_input` 的 `cell_right`（右键） |
| | `on_cell_click` 双击撤销分支 | 撤销第一击切出来的 ✗（定位：`core:toggle_x(r, c)` 在 `last.did == "x"` 分支内） |
| | `Core:tap_cell` × 2 | X 模式 / 没选人时单击（均 `, nil`） |
| `erase_cell` | `Core:tap_cell` × 1 | 橡皮擦模式（`, nil`） |
| `toggle_note`（local） | `Core:tap_cell` × 2 | MODE_NOTE 与 place 模式（**现已双双透传**） |
| `set_mode` | `ui_controller.lua:1387` | `on_input` 的 `tool` 分支 |
| `select_suspect` | `ui_controller.lua:7222` / `7226` | `_on_grid_item_click`（`6911` 定义；点线索卡选中/取消那个人） |
| | `ui_controller.lua` 的 `a == "reveal"` 分支 | 逐人 `select_suspect(id)` + `hold_cell` |
| | `main.lua:2216` | `SYNC_STATE` |
| `tap_suspect`（= `select_suspect`） | `on_input` 的 `a == "suspect"` 分支 | `core:tap_suspect(event.id)` |
| `do_place`（local） | `Core:hold_cell` / `Core:pre_place` | `clear_notes = true` / `false` |
| | `Core:decode_state` / `Core:undo` / `Core:redo` / `Core:hint` | **`record = false` ⇒ 绕开一切规则检查**（对 R1 极重要，见 §2.3c） |
| `do_clear`（local） | `Core:move_piece_if_needed` / `tap_cell`「拿起」/ `Core:erase_cell` / `Core:undo` / `Core:hint` | — |

**`lua/entry_client_script.lua` 不直接调任何核心动作方法** —— 只做启动与 `cfg` 配置
（`cfg.cells_beacon` / `cfg.btn_art` / `cfg.cells.prefab` / `cfg.prefab_of` / `cfg.debug_*`）。

**`dist/client_script.lua` 是上述模块的拼装产物**（同样内容见 `:3727` `_refuse`、`:6116` `notes`、`:6172` `x_mark`）。
**改 `lua/` 后必须重新打包，不要手改 dist。**

---

## 4. 绘制通路细节（`build_layout` = `ui_controller.lua:2124`）

### 4.1 数据源：核心 `view()`，UI 不缓存

| 字段 | 来源 |
|---|---|
| `cd.notes` | `sorted_keys(self.notes[r][c])` —— **id 的数组**（⚠️ 见 §1 Q2：`build_layout` 实际不用它） |
| `cd.x` | `self.x_marks[r][c] == true` |
| `cd.occupiable` | `not self:is_blocked(r, c)` |
| `cd.state` | `cell / blocked / filled / victim / wrong / hint`（顺序覆盖） |

### 4.2 每格 `push({...})` 的字段（快照行号）

| 字段 | 行 | 值 |
|---|---|---|
| `id` / `parent` | — / `3101` | 格子名 / **父级 `stage`**（真机实测 `board` 不存在） |
| `visible` | `3135` | `self.screen == nil`（主页/选关藏掉） |
| `image` | `3182` | `cd.suspect and Controller.portrait_of(...) or false` ← 人 |
| **`notes`** | **`3210`** | **`_note_val or false`** ← 铅笔字母 |
| `object` | `3234` | `Controller.object_key_of(...) or false` ← 家具 |
| `tint` | `3257` | 有棋子 ⇒ 白色（不染色），否则房间色 |
| `hint` | `3259` | 提示层布尔（每格都发 true/false） |
| `fit` | `3264` | 格子边长（画布） |
| `occupiable` | `3265` | 透传给适配器，UI 自己不判 |
| **`x_mark`** | **`3266`** | **`cd.x`** ← ✗ |
| **`enabled`** | **`3267`** | **恒 `true`**，注释：「不可站人的格子也要能点（用于打 X / 提示原因）」 |
| `event` | `3268` | `{ action = "click", r = r, c = c }` |

`notes` 取值步序：**先** `core.notes[r][c]`（集合），**取不到再** `cd.notes`（数组）。
`mark_list_of`（`446-460`）把 id 换成 `letter_of(人)`，无配置则回退 id。

### 4.3 `style` 通道对格子是**视觉空转**（别往这里挂钩）

`ui_controller.lua` 内（快照 `3069-3084` 附近）：

```lua
local style = "cell"
if cd.state == "blocked" then style = "cell.blocked"
elseif cd.state == "victim" then style = "cell.victim"
elseif cd.state == "hint"   then style = "cell.hint"
elseif cd.state == "wrong"  then style = "cell.wrong" end
if cd.x then style = "cell.x" end                                   -- :3080  ✗ 覆盖上面四个
if self.kb_active and self.kb.r == r and self.kb.c == c then
  style = "cell.cursor" end                                         -- 光标覆盖一切
```

优先级：`cell.cursor` > `cell.x` > `cell.{blocked,victim,hint,wrong}` > `cell`。

**但适配器不认识任何 `cell.*` 样式**：
- `Adapter:scale_of_style`（`engine_adapter_qianxing.lua:2627-2634`）只有 `portrait*` / `clue.focus` / `tab.active`
- `Adapter:color_of_style`（`2647-2655`）只有 `clue.*`
- `key == "style"` 分支（`4592-4633`）只做缩放 / 文字色 / 头像减淡；`self._style[id]`（`4609`）仅供重排复算缩放

⇒ **`cell.blocked` / `cell.x` 在画面上零效果。** blocked 外观完全由模板/编辑器配置决定；
✗ 与字母完全由 `x` / `note` 子控件决定。**新规则不要试图用 `style` 表达。**

### 4.4 序列化格式**已经**假定「✗ 优先于笔记」

- `Core:encode_state`：`if self.x_marks[r][c] then tokens .= "X"` —— **在检查 `grid` 和 `notes` 之前**
  ⇒ ✗ 与笔记同时存在时，笔记被静默丢弃。
- `Core:decode_state`：`"X"` 分支只置 `x_marks`，笔记分支只置 `notes` —— 天然互斥。
- 本轮又加了 §2.5 的两道不变量（`serialize` 写出前、`decode_state` 读入时）。

⇒ **在核心层强制 notes/✗ 互斥，与既有分享码/存档契约同向，不会破坏往返测试。**
（`tests/selftest.lua:333-336` 的「笔记还原 / ✗ 还原」用的是**不同格子**，安全。）

---

## 5. UI 侧预门控：核心拒绝可达吗？

### 5.1 结论：**基本没有预门控，核心拒绝可达**

- 格子 `enabled = true` 恒真（`ui_controller.lua:3267`）。
- `event = { action = "click", r = r, c = c }`（`3268`）对所有格子都挂。
- `on_cell_click`（`1044`）唯一的提前返回是**坐标缺失**：`1054`
  `if r == nil or c == nil then return end`
  （适配层 `_fire` 在拿不到节点事件时发 `{action="click"}` 兜底，见 `engine_adapter_qianxing.lua:4774+`）。
- `on_cell_down`（`964`）/ `on_cell_up`（`972`）/ `on_cell_drag`（`1031`）**不看** `blocked` / `occupiable`。

⇒ blocked 格、同行同列格**都能点到**，都能进 `core:tap_cell` / `core:hold_cell` ⇒ **核心拒绝可达**。
（可达 ≠ 可见：可见性取决于 §2 的原因串透传。）

### 5.2 唯一分支差异：双击只对**空格**生效

`on_cell_click` 内 `if (not occupied) and mode == "place" then` —— 双击预放置只处理空格。

### 5.3 `flush_pending_note` 现在几乎是死路

`self.pending_click` 只在 `on_key` 的 `note` 分支被设值（快照 `1277`：`self.pending_click = { r = kb.r, ... }`）；
`on_cell_click`、`do_place`、`do_pre_place` 里都置 `nil`。
⇒ `_refuse@854` **只在键盘 Space 打笔记被拒时**可能触发，覆盖面极小。

### 5.4 `main.lua` 的旁路

`Murdoku.on_signal` 的 `SYNC_STATE`（`main.lua:2214-2219`）调 `select_suspect` + `tap_cell` 后**丢弃返回值**
⇒ 服务端同步来的动作即使被规则拒绝也**没有任何提示**。若服务端真会下发该信号，需在此补 `_refuse` 或日志。

---

## 6. UI 是否重复缓存规则状态（漂移风险）

| 状态 | 结论 | 证据 |
|---|---|---|
| `x_marks` | **不缓存**，每帧取 `cd.x` | `ui_controller.lua:3266` ← 核心 `view()` |
| `notes` | **不缓存**，直接读 `core.notes[r][c]` | `build_layout` 内 `_note_val = mark_list_of(core.notes[r][c] ...)` |
| `placed` | **不缓存**，直查 `core.placed[id]` | `ui_controller.lua` 的 `do_place` 调试分支、`_fill_grid_item` 的灰白判据 |
| `row_count` / `col_count` | **UI 完全不读**（全仓 grep 仅核心命中） | — |
| `blocked` / `occupiable` | UI 只透传 `cd.occupiable`（`3265`），自己不判 | — |
| **样式缓存** | `Adapter._style[id]`（`engine_adapter_qianxing.lua:4609`）供重排复算缩放 | 对 `cell.*` 无效果（§4.3） |
| **选中高亮** | `_grid_focus_*` / `focused_clue` 与 `core.selected` **是两套**，放置后手动一起清 | `do_place` 内撤高亮那段；`_on_grid_item_click` 明确警告「派生值当判据 = 把因果倒过来」 |

⇒ **三条新规则不引入状态漂移风险**：`x` / `notes` / `blocked` 都只有一个真源（core 的表），UI 每帧现算。

---

## 7. 关于「挂到 toast 上」的可行性警告

`self.toast` 机制**存在但关卡内没有出口**：
- 写入点多处（`ui_controller.lua` 内多处，＋ `main.lua:355/487`）
- 唯一读出点 `Controller:toast_text()`（`ui_controller.lua:2116`）
- 唯一消费点 `home.title`（`ui_controller.lua:3771`：`text = self:toast_text() or M.HOME_TITLE`）
- `hud.toast` / `hud.subtitle` 已按用户指令**删除**（`toast_text` 上方注释与 `M.EFFECTS` 下方注释都写着：
  「**关卡内的 toast 目前无处显示**」）

⇒ **把拒绝原因写进 `self.toast`，在关卡内看不见**（等于换一种静默）。
真要上屏须**新开控件位**：编辑器 `.gil` 建控件 ＋ `build_layout` 里 `push` ＋ 跑
`node tools/gil/check_names.mjs`（`entry_client_script.lua:326` 记着「规划里有、.gil 里没有 = 🔴 真缺」；
`engine_adapter_qianxing.lua:427` 同）。**这是新增控件的工作量，不是一行赋值。**

**无需新增控件的现成视觉通道**：`Controller:fx(target, kind)`（`ui_controller.lua:340`）＋ `M.EFFECTS`（`:258`）。
其中 `FAIL = "shake"`（`:269`）目前**只用于结案弹窗**（`do_submit` 失败的 else 分支），可复用作
「这一格被拒」的抖动，且不影响 `_refuse` 的 3 次上限逻辑。

---

## 8. 会因新规则变化的既有契约

| 位置 | 现内容 | 关系 |
|---|---|---|
| `tests/selftest.lua:326`（注释） | 「`blocked` 只表示"不能站人"，**✗ / 笔记**是玩家的推理痕迹，任何格子都能打」 | **与已落地的规则 B 直接矛盾**，注释需改写 |
| `tests/selftest.lua:327`（断言） | `check("不可站人的格子**能**打 X", core:toggle_x(1, 5) == true)` | **仍然通过**（`toggle_x` 未加门控）⇒ 断言可留，但**必须补一条「障碍格不能打笔记」的新断言** |
| `tests/selftest.lua:322` | `check("书桌所在格不可站人", core:is_blocked(1, 5))` | 不变 |
| `tests/selftest.lua:344/353/354` | `one_per_row = false` + 同行放两人 | **R1 必须按规则开关放行**，否则红 |
| `tests/selftest.lua:320` | `core:tap_cell(3, 2)` 打笔记 | (3,2) 不是障碍格，安全 |
| `Core:do_place` 的 `auto` 注释 | 「两条"自动整理"规则的**强度由 opts 决定**」 | 规则 X 已加第三件事（`x_notes`）⇒ 注释需补第三条 |
| `docs/规则规格-偷窃版.md`（8 011 B） | 规则规格 | **未读**，见 §9 |

⚠️ **规则 X 让 `do_place` 现在会擦掉同行同列的所有笔记** ⇒ 任何「先打笔记、再在同行同列放人、又断言笔记还在」的测试都会红。
**未逐条跑测试**（属 recon-build 的基线职责）。建议基线口径：至少单独跑
`tests/selftest.lua`、`tests/cell_mark_letter.lua`、`tests/board_wiring_e2e.lua`、`tests/gray_unplace.lua`。

---

## 9. 未验证 / 需他人接手

1. **`tools/bundle_client_script.lua` 的打包命令与产物校验** —— 未执行。`dist/client_script.lua`
   确认是拼装物（内容逐一对应、行号偏移），改 `lua/` 后需重新打包；重建/测试流程属 recon-build。
2. **`tools/check_all.ps1` / `run_checks.ps1` / `lua_lint.ps1` 当前是否全绿** —— 未执行（基线归 recon-build）。
3. **源文件多处注释引用旧行号，已漂移**（例：`ui_controller.lua` 里引「`ui_controller.lua:2677~2680`」；
   `engine_adapter_qianxing.lua:4795` 引「`ui_controller.lua:818-823`」）。
   **本报告行号是快照值；注释里的旧引用不要当依据。**
4. **`docs/规则规格-偷窃版.md` 与 `docs/技术架构.md` 未读** —— 若其中已定义三条新规则的文案口径，
   应优先采用文档措辞而非本报告的临时建议字符串。
5. **服务端是否真的会下发 `SYNC_STATE`** —— 未验证（`main.lua:2214`）。若会，该路径的拒绝是静默的（§5.4）。
6. **`Core:hold_cell` 里「长按橡皮擦 = 清空全盘」那段很可能是死代码** ——
   它前面有 `if not self.selected then return false, "先点一个头像" end`，而 `Core:set_mode` 进入 `MODE_ERASE`
   时会把 `selected` 置 nil（`Core:select_suspect` 又会把模式切回 `MODE_PLACE`）⇒ 该分支疑似永不执行。
   **仅静态推断，未写测试验证**；改动 `hold_cell` 时值得确认。
   （`tests/selftest.lua:299-314` 记着「双击橡皮擦清空全盘已移除」，与此相关但对象不同。）
