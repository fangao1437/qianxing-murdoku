# RECON · 构建 / 测试 / 模拟器管线 与 干净基线

> 任务：task-2（recon-build）。写于 2026-10-20 05:4x。
> 本文只记录**我实际跑出来的东西**；推断与未跑项在第 8 节单独列出。
> ⚠️ 本次侦察期间**有别的 teammate 在并发改 `lua/**`**（见 1.3），所以给了两个时间点的快照。

---

## 0. TL;DR

| 问题 | 答案 |
|---|---|
| 改完 `lua/murdoku_core.lua` 后怎么验？ | §3-A 五行命令，全 exit 0 才算过；全量闸门见 §3-B |
| 离线全量套件现在绿吗？ | `tests/` **39 个文件全部 exit 0**：33 个真套件 **≈1007 断言 / 0 失败** ＋ 3 个自跳过 ＋ 3 个夹具。7 个校验步骤里 3 绿（`check_nesting` / `lua_quote_scan` / `lua_lint`）4 红——**只有 `check_actions` 是本轮新增的红**（且是假阳性），另 3 个（`check_encoding` / `normalize_encoding -Check` / `bump_build_marker --check`）是历史遗留（§5） |
| `.gil` 里嵌的脚本是新的吗？ | T1 时 `存档/466-…v278.gil` 里的脚本与 `dist` **逐字节相同**（sha 一致、标记 v278）；T1 之后源码升到 **v279**，`466` 已过期，需要重新 embed |
| 能从最新 `.gil` 造出模拟器存档吗？ | **能**。已产出 `tools/sim/out/current.save.json`（format=`qxqy-simulator-save`，**369 控件 / 0 脚本**），UI 树与 v279 档**逐字段相同** |
| 存档里带 Lua 吗？ | **不带**（`scripts: []`、`assets.scripts: []`）。转换器只搬 UI；Lua 要另行挂（§6.3） |

---

## 1. 环境与基线快照

### 1.1 工具链（实测）

| 项 | 值 |
|---|---|
| shell | **Windows PowerShell 5.1.26100.9711**（`pwsh` 工具实际起的是 5.1 ⇒ 命令里**不能**用 `?:`、`??`） |
| Lua | `C:\Users\18182\AppData\Local\Programs\Lua\bin\lua.exe` = **Lua 5.4.6**，且 `lua` 在 PATH 上 |
| Node | **v24.21.0** |
| fengari（Lua 5.3 检查用） | 已装在 `tools/lua53check/node_modules` ✓ |
| git | 2.55.0（`C:\Users\18182\AppData\Local\Programs\ds-harness-desktop\runtime\git\cmd\git.exe`） |
| 执行策略 | Restricted ⇒ `.ps1` 只能 `powershell -ExecutionPolicy Bypass -File …` 起 |
| selene / stylua | `tools/bin/selene/selene.exe`、`tools/bin/stylua/stylua.exe` 都在 ✓ |

### 1.2 git 基线：**脏树**（不动它，只记录）

`HEAD = 01a151f`（2026-10-18 10:40:40，v270 那轮）。
T1（05:40）时 `git status --porcelain` = **12 个 M + 28 个 ??**：

```
M  dist/client_script.lua            M  lua/engine_adapter_qianxing.lua   M  lua/entry_client_script.lua
M  lua/main.lua                      M  lua/murdoku_core.lua              M  lua/ui_controller.lua
M  tests/btn_art_gate.lua            M  tests/entry_smoke.lua             M  tests/grid_cost.lua
M  tests/perframe_throttle.lua       M  tests/selftest.lua                M  tests/ui_math.lua
?? docs/…（12 篇优化组/审计回执）   ?? tools/audit/_p0_delete_batch{2..9}.mjs（8 个）
?? 存档/459…466（8 个 .gil）
```

### 1.3 ⚠️ 基线在侦察期间被并发改动（必须知道）

| 时间 | 事件 | 证据 |
|---|---|---|
| 05:40 | T1 快照：源码标记 **v278**，`dist` = 1 282 324 B / sha `46299C85…` | §4 |
| 05:43:31 | 新文件 `tests/rule_guards.lua` 出现（99 断言，测新规则） | 文件 mtime |
| 05:45:26–05:45:59 | `murdoku_core.lua` / `ui_controller.lua` / `entry_client_script.lua` / `tests/selftest.lua` 被改，标记升到 **v279**（"同行/同列已有别人 ⇒ 拒绝放置"三条新规则） | mtime + `构建标记 v279` |
| 05:46:18 | 有人产出 `tools/_wip/{base,out}_v279.gil`（两者**逐字节相同**），内嵌脚本 = v279 的 `dist` | sha 比对 |
| 05:46:48 | 我按闸门要求重跑 bundle ⇒ `dist` = **1 295 427 B / sha `14034A28…`（v279）** | `$LASTEXITCODE=0` |

⇒ **T2 复核（v279）依旧全绿**（§4.2）。但如果 Lead 的改动与这批并发改动重叠，请以你手上的源码为准重跑。

---

## 2. 交付链（实测，一条不缺）

```
lua/entry_client_script.lua + lua/{room_map,murdoku_core,ui_controller,engine_adapter,
engine_adapter_qianxing,main,levels/init}.lua
        │  lua tools/bundle_client_script.lua          （去掉 BOM、按模块顺序拼、空模块直接拒绝打包）
        ▼
dist/client_script.lua                                  （单文件，客户端脚本页映射的就是它）
        │  node tools/gil/embed_script.mjs --in=<用户的档> --out=<新档>
        │    · 无条件核对"源码标记 == dist 标记"，不等就 exit 1 拒绝运行
        │    · 写入走 writeGil：落盘→重读→往返闸门→字段 diff 恰好 1 处→标记断言
        ▼
存档/<NNN>-<名字>-v<NNN>.gil                             （★ 用户在真编辑器里导入的是这一份）
        │  node tools/sim/gil_to_save.mjs --in=<档> --out=<x.save.json>
        ▼
qxqy-simulator-save JSON                                 （DSH 模拟器 / 本仓 tools/sim/*.mjs 用）
```

**判据（三条都是硬判据，不是我定的）**

1. `lua tools/bundle_client_script.lua` → 末尾打印 `模块 N 个，总长 …`，exit 0；任一模块"只剩 <64 个有效字符"会 `exit 2`（防"文件被写空"事故）。
2. `node tools/gil/embed_script.mjs --probe --in=<档>` → `★ 内容已经是最新的，无需改动。`（脚本已同步）或正常产出 + `★ 导入这个存档就是 v<NNN> 脚本`；自检不过 `exit 3`。
3. 出货后再 `node tools/gil/roundtrip.mjs <新档>`（逐字节往返）+ `node tools/gil/diff_fields.mjs <旧> <新>`（**差异应恰好 1 处**）+ `node tools/gil/check_names.mjs <新档>`（`★ 对账通过`）。

**T1 实测证据（`存档/466-删老线索卡v278.gil`）**

```
node tools/gil/embed_script.mjs --probe --in="存档/466-删老线索卡v278.gil"
  版本链：源码 entry_client_script.lua = v278　dist = v278
  存档内现有脚本：1282324 字节 @/#50/#1/#5，标记 v278
  ★ 内容已经是最新的，无需改动。                                   exit 0
node tools/gil/roundtrip.mjs "存档/466-…v278.gil"
  ★★★ 往返成功：重新编码与原始体逐字节完全一致                     exit 0
```
我另外用自写探针把内嵌叶子取出来算 sha256：**embedded == dist == `46299C85…`（1 282 324 B）**，两边标记都 `v278` ⇒ "导入即最新"成立。
`check_names.mjs` 在 `tools/_wip/base_v279.gil` 上 exit 0：`★ 对账通过：脚本【运行必须】的名字全部存在`。

---

## 3. 复制即用的命令清单

### 3-A 最小闭环（改完 `lua/murdoku_core.lua` 必跑；幂等、不写别的东西）

```powershell
cd "D:\新建文件夹\miHoYo Launcher\qianxing-murdoku"
$lua = "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe"

& $lua tools/bundle_client_script.lua                          # 1) 打包（改 lua/** 之后必须重跑）
& $lua tests/selftest.lua                                      # 2) 规则引擎   v279: 63 通过
& $lua tests/rule_guards.lua                                   # 3) 放置守卫 / 笔记×✗ 互斥  99 通过
& $lua tests/input_logic.lua                                   # 4) 手势状态机  64 通过
& $lua tools/validate_levels.lua 3                             # 5) 三关数据：0 项待处理
node tools/lua53check/check.cjs dist/client_script.lua --run    # 6) Lua 5.3 编译 + 顶层执行
```
每条都打印 `exit=$LASTEXITCODE` 更稳。**`bundle` 的 exit code 一定要看**：它是所有产物的唯一入口。

### 3-B 全量离线闸门（39 个 tests 文件 + 静态检查；跑一遍约 2 分钟）

```powershell
cd "D:\新建文件夹\miHoYo Launcher\qianxing-murdoku"
$lua = "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe"
$fail = @()
foreach ($t in (Get-ChildItem tests -Filter *.lua | Sort-Object Name)) {
  & $lua $t.FullName | Out-Null
  if ($LASTEXITCODE -ne 0) { $fail += $t.Name }
}
if ($fail.Count) { "FAILED: $($fail -join ', ')" } else { "ALL tests PASS (exit 0 each)" }

node tools/lua53check/check.cjs dist/client_script.lua --run
& $lua tools/validate_levels.lua 3
node tools/audit/check_nesting.mjs      # 期望 exit 0：0 嵌套 / 0 节流嵌套
node tools/audit/check_actions.mjs      # ★ 现在 exit 2（见 §5.1，历史/假阳性红）
node tools/check_encoding.mjs           # ★ 现在 exit 1，13 项 BOM 违规（见 §5.2）
powershell -ExecutionPolicy Bypass -File tools/lua_quote_scan.ps1   # 期望 exit 0
powershell -ExecutionPolicy Bypass -File tools/lua_lint.ps1         # 只报告，永远 exit 0
```
> `tests/` 里 3 个是**夹具**（`fixtures.lua`、`old_case_001.lua`、`old_case_002.lua`，直接跑是空转 exit 0），
> 3 个是**自跳过**（`anchored_pos_guard` / `dupe_dispatch` / `overlap_diag_once`：功能已回退，打印 `⊘ 本环境测不了`，exit 0）。
> 39 − 3 − 3 = **33 个真正在断言的套件**。

### 3-C 出货 `.gil`（★ 每次交付前）

```powershell
cd "D:\新建文件夹\miHoYo Launcher\qianxing-murdoku"
& $lua tools/bundle_client_script.lua
node tools/gil/find_script.mjs "存档/<最新>.gil"                                   # 看里面嵌的是多大
node tools/gil/roundtrip.mjs "存档/<最新>.gil"                                     # 判据：逐字节一致
node tools/gil/embed_script.mjs --probe --in="存档/<最新>.gil"                      # 不写文件，先看链
node tools/gil/embed_script.mjs --in="存档/<最新>.gil" --out="存档/<新名>.gil" --expect-marker=v<NNN>
node tools/gil/roundtrip.mjs "存档/<新名>.gil"
node tools/gil/diff_fields.mjs "存档/<最新>.gil" "存档/<新名>.gil"                   # 差异应恰好 1 处
node tools/gil/check_names.mjs "存档/<新名>.gil"                                   # ★ 对账通过
```
> ⚠️ `bump_build_marker.mjs` 的 `--check` 与"递增"两条路**现在都坏了**（§5.3）。在它修好前，
> 升标记是**手改** `lua/entry_client_script.lua` 里那一行 `构建标记 vNNN / YYYY-MM-DD / 说明`，再跑 bundle。

### 3-D 造模拟器存档 + 载入

```powershell
cd "D:\新建文件夹\miHoYo Launcher\qianxing-murdoku"
node tools/sim/gil_to_save.mjs --in="存档/466-删老线索卡v278.gil" --out="tools/sim/out/current.save.json"
#   ↑ 会同时写 current.save.summary.json 与 current.save.warnings.txt（转换报告）
# 然后在会话里：qxqy_studio_load { "path": "qianxing-murdoku/tools/sim/out/current.save.json" }
# 只载 UI；要让 Lua 跑起来见 §6.3（转换器不带脚本）
```

---

## 4. 基线结果（逐套 pass/fail）

### 4.1 T1 快照（v278，`dist` sha `46299C85…`）—— 全量跑了一遍

| 步骤 | exit | 结果 |
|---|---|---|
| `tools/bundle_client_script.lua` | 0 | 模块表 7 个 + init 动态引入；**重跑产物与跑前逐字节相同**（不污染 git） |
| `tools/lua53check/check.cjs dist/client_script.lua --run` | 0 | `LOAD OK 870883 字符 / 20759 行` + `RUN OK`；四个生命周期函数都在 |
| `tools/validate_levels.lua 3` | 0 | 3 关全 OK；`合计 3 关…需要处理的 0 项`（case_003 假话"未测：本关线索 0 条"是已登记待设计，不是判据失效） |
| `tools/audit/check_nesting.mjs` | 0 | `扫描 14 个 .lua；[嵌套] 0 处；[节流嵌套] 0 处` |
| `tools/audit/check_actions.mjs` | **2** | 见 §5.1 |
| `tools/check_encoding.mjs` | **1** | 13 项 BOM 违规，见 §5.2 |
| `tools/lua_quote_scan.ps1` | 0 | 无奇数双引号 |
| `tools/lua_lint.ps1` | 0 | 只报告：79 条（71 unused_variable / 7 empty_if / 1 ifs_same_cond），**1 条 error** = `ui_controller.lua:3580 ifs_same_cond`；`0 parse errors` |
| `normalize_encoding.ps1 -Check` | **1** | 4 个文件 BOM 状态不对（§5.2 的子集） |
| `bump_build_marker.mjs --check` | **1** | 见 §5.3 |
| `tools/dump_layout.lua all tools/_wip/layout-plan.json` | 0 | `并集控件 135 个`（默认落 `tools/sim/out/layout-plan.json`，我改到 `_wip` 以免覆盖既有产物） |

逐套（39 个文件，T1 跑 38 个，`rule_guards.lua` 05:43 才出现、单独跑）：

| 套件 | exit | 断言 |
|---|---|---|
| selftest.lua | 0 | 60 通过 / 0 失败（另 3 条 `⊘ 已删功能`） |
| ui_math.lua | 0 | 60 通过 |
| rule_guards.lua | 0 | **99 通过**（P1–P9 放置守卫 / X1–X9 笔记×✗ / B1–B5 障碍格 / R1–R4 不变量） |
| input_logic.lua | 0 | 64 passed |
| entry_smoke.lua | 0 | 61 条 `[PASS]`（该套件无汇总行） |
| clue_hint.lua | 0 | 90 通过 |
| selection_residue.lua | 0 | 63 passed |
| clue_slots.lua | 0 | 56 passed |
| things_wiring.lua | 0 | 43 通过 |
| select_hit_visible.lua | 0 | 42 passed |
| effects_wiring.lua | 0 | 38 passed |
| board_bg.lua / grid_cost.lua | 0 | 28 passed / 28 passed |
| settle_button.lua / simple_level.lua | 0 | 22 / 22 |
| edge_center.lua | 0 | 21 passed |
| hide_safety.lua / gray_unplace.lua | 0 | 18 / 18 |
| cell_lightup_size.lua / wall_overlap.lua | 0 | 16 passed / 16 passed |
| bound_rearm.lua | 0 | 15 通过 |
| board_wiring_e2e.lua | 0 | 14 passed |
| cell_mark_letter.lua | 0 | 14 passed |
| prop_ledger.lua | 0 | 13 passed |
| sub_miss_cache.lua | 0 | 12 通过 |
| btn_art_gate.lua / confirm_card_anchor.lua / level3_letter_map.lua / perframe_throttle.lua | 0 | 11 / 11 / 11 / 11 |
| row_letter_map.lua | 0 | 9 passed |
| card_fit_gate.lua / row_letter_stability.lua | 0 | 8 / 8 |
| tree_ref_reconcile.lua | 0 | 2 通过（对账器自测） |
| anchored_pos_guard / dupe_dispatch / overlap_diag_once | 0 | **⊘ 自跳过**（功能已回退；6/7/10 条断言等复活） |
| fixtures / old_case_001 / old_case_002 | 0 | 夹具，无断言 |

**合计 ≈ 1004 条断言，0 失败。**

### 4.2 T2 复核（v279，`dist` sha `14034A28…`，1 295 427 B）

按 §3-B 原样跑了一遍：**39 个 tests 文件全部 exit 0**；`lua53check RUN OK`（`879146 字符 / 20969 行`）；`validate_levels` 0 项；
`check_nesting` 0 处；`selftest` 涨到 **63 通过**、`rule_guards` **99 通过**、`ui_math` 60、`input_logic` 64、`clue_slots` 56。
静态检查三项的红与 T1 相同（§5）。

---

## 5. 现存的红：**本轮新增** 与 **历史遗留** 分开列

### 5.1 `tools/audit/check_actions.mjs` → exit 2 ✅**本轮新增**，且是**假阳性**

```
[!] 发出但【没有处理分支】的 2 个：
  intro_next                 发出处 ui_controller.lua:618
  intro_skip                 发出处 ui_controller.lua:618
```
- 根因：`ui_controller.lua:618` 是**注释**（`-- 事件格式：… {action="intro_next"} | {action="intro_skip"}`），
  而 `check_actions.mjs` 用裸正则 `/action\s*=\s*"([a-z_]+)"/g` 扫**原始行**，不剥注释。
- 为什么是"新增"：`git show HEAD:lua/ui_controller.lua` 里 `intro_next/intro_skip` 有**真实发射点**（L3746/L3748）
  且有**处理分支**（L1514/L1521）⇒ HEAD 上这一步是绿的；未提交的 v273"删教程"把两边都删了、只留下这条注释。
- 两种修法（都很小）：① 删掉注释里那两个 `{action="intro_next"} | {action="intro_skip"}`；② 让 `check_actions.mjs` 先剥 `--` 注释再扫。
  **不要**为此放宽判据。

### 5.2 `tools/check_encoding.mjs` exit 1（13 项）/ `normalize_encoding.ps1 -Check` exit 1（4 项）— 🟡**历史遗留**

13 个文件全是 **git 里已提交且未修改**的文件 ⇒ 在 HEAD 上同样是红的（与本次改动无关）：

```
docs/production-plan.md · docs/回执-门墙居中格线-v265.md · docs/技术架构.md   （多了 BOM，应无）
tests/edge_center.lua                                                      （多了 BOM；打包会被 bundler 剥掉，但这违反工程规约）
tools/gil/copy_state_floats.mjs · tools/sim/{_make_v240_like,_probe_save,_probe_save2..5,_strip_children,_variant}.mjs  （多了 BOM）
```
`normalize_encoding -Check` 的 4 项 = 上面 3 个 `.md` + `tests/edge_center.lua`（它只处理 md/lua/ps1）。
修法：`powershell -ExecutionPolicy Bypass -File tools/normalize_encoding.ps1`（无 `-Check` 就会就地修）+ `node tools/check_encoding.mjs` 复查。
> 我控过噪声：侦察期间我自己在 `tools/_wip/` 造的临时文件曾把这项顶到 18 项，**已全部清掉**，现在 13/4 就是历史值。

### 5.3 `tools/bump_build_marker.mjs --check` exit 1 — 🟡**历史遗留（HEAD 上同样红）**

```
✗ 在 lua\entry_client_script.lua 里找不到构建标记（形状应为 `构建标记 vNNN / YYYY-MM-DD / 说明`）
```
- 根因：脚本的正则是 `/构建标记 (v\d{2,4}) \/ (\d{4}-\d{2}-\d{2}) \/ ([^"\\]*?)(?=\s*=====)/` ⇒ **要求标记后面还有 `=====`**。
- 现状：现行那一行是 `print("[murdoku] ===== 构建标记 v278 / … （彻底消除 1×1 漏光）")` —— `=====` 在**前面**，尾部没有。
- 我用该正则直接跑了 `HEAD:lua/entry_client_script.lua` ⇒ **NULL**，跑工作区文件 ⇒ **NULL** ⇒ **HEAD 上就是红的**。
- 历史形状：`versions/144-v224` … `148-v240` 的 `client_script.lua` 该行**都以 `=====")` 结尾**，所以严格说是在 v240→v270 之间丢的（具体提交没查，`git log -S` 没出结果，时间预算内放弃）。
- 影响：`--check` 红（`check_all.ps1` 的 2c2 步骤）；**递增模式也一起坏**（`src.replace(RE, …)` 不生效 ⇒ `exit 1`）。
- 两条修法：① 把那一行末尾补回 `=====`（同时让 `--check` 与递增都恢复，且不影响 `entry_smoke` 的"第一行含『画布』"断言）；
  ② 修正则，去掉尾部 lookahead（并给 `[^"\\]` 加上"非贪婪到行尾"）。

### 5.4 `lua_lint.ps1` 的 1 条 error（只报告，不阻塞）— 🟡历史遗留
`ui_controller.lua:3580 [ifs_same_cond]`（与 L3499 的 if 条件相同）。属"读代码能看出来"的那类，改不改是作者决定。

---

## 6. `.gil` → 模拟器存档（真跑了）

### 6.1 命令 + 实际输出

```powershell
node tools/sim/gil_to_save.mjs --in="存档/466-删老线索卡v278.gil" --out="tools/sim/out/current.save.json"
```
```
records 369 · controlsInOutput 369 · scaffoldDropped 20 · warnings 245 · designNodes 0 · canvasAbsoluteNodes 1
kinds: button 45 · container 57 · image 132 · textbox 130 · reference 4 · grid 1
in  sha256 6978DF9E… （"存档/466-删老线索卡v278.gil"，1 584 952 B）
out sha256 0AEB2E32… （"tools/sim/out/current.save.json"，1 562 995 B）        exit 0
```

### 6.2 产出文件的形状（`tools/sim/out/current.save.json`）

| 项 | 值 |
|---|---|
| `save.format` | **`qxqy-simulator-save`**（注意：在**第 78683 行**，是 `save` 子对象里的字段，不是文件头；与既有的 `453-v265.save.json` 完全一致） |
| `version` / `layoutSchemaVersion` | 1 / 2（与既有存档一致） |
| `canvasId` | `pc-16-9`（1600×900 / KEYBOARD） |
| 控件数 | **369**（`root` 递归 369 节点 = `boxes` 369 = `tree` 369 行） |
| 脚本数 | **0**（`scripts: []`、`assets.scripts: []`）、`mountTargets: 0` |
| `meta` | `{"name":"466-删老线索卡v278","sourceFormat":"gia","gameVersion":"7.1.0","giaFilePath":"…\\存档\\466-…v278.gil"}` |
| 顶层键 | 与既有 `453-v265.save.json` **18 个键完全相同** |

### 6.3 它"能载入"到什么程度（诚实版）

- ✅ **结构上可以载入**：与 `453-v265.save.json`（本工程历史上真被 `qxqy_studio_load` 载进会话的那份，
  见 `docs/转换器-gil到模拟器存档.md`："`qxqy_studio_load { "path": "qianxing-murdoku/tools/sim/out/371-v240.save.json" }`…本次实测用的就是这条"）
  **同键集、同 format、同 schema 版本**；控件数 369 vs 368（差异就是 +1 个 textbox）。
  ⚠️ 但**我没有实际调用 `qxqy_studio_load`**（说明见 §8.3）——"载入成功"这一步留给 Lead。
- ⚠️ **它不含 Lua**：`gil_to_save` 只搬 UI 树。要在模拟器里真玩起来，Lua 得另外挂：
  · 路线①（本仓已有、最省事）：`node tools/sim/play_test.mjs` 之类——它们**不读这份 json**，而是用
    `tools/sim/kit.mjs` 的 `buildProject()` 按 `layout-plan.json` 现场建树，并 `addScript{path,source,controlId=tplRoot,controlAsset:'client'}`
    把 `dist` 挂到**临时建的客户端模板**上（同一个 Node 进程里建树+试玩，因为模拟器状态是内存态）。
  · 路线②（会话内）：先 `qxqy_studio_load` 载当前存档，再用 `qxqy_studio_patch` 补客户端模板 + `addScript` 把
    `dist/client_script.lua` 作为内联 `source` 挂上去（`scripts[].source` 非空时优先于 `path`）。
  · ⚠️ 本仓 `sim-save/`（`.gitignore` 里）已**不存在**，所以"带脚本的现成存档"现在没有——这也是 `rebuild_save_script.mjs`
    暂时没源档可用的原因。

### 6.4 附带的强证据：这份存档对 **v279** 也有效

我把 teammate 的 `tools/_wip/base_v279.gil` 也转了一份到 `_wip` 比对：
`tree` / `boxes` / `root` 的 sha256 **三者全部相同**（`66FF6D49…`）⇒ v278→v279 只改了 Lua，**UI 控件树一字未动**。
所以 `tools/sim/out/current.save.json` 的 UI 就是当前最新 UI；只是 `meta.sourceFile` 还写着 v278 的档名。

---

## 7. `murdoku_core.lua` 三条规则 → 测试锚点

| 规则（core 侧） | 覆盖套件 | 锚点（可以直接 grep 的字符串） |
|---|---|---|
| **放置**：正式放置 `hold_cell` / 双击 `pre_place` / 单击 `tap_cell` / 拿起 `do_clear` / 障碍格拒绝 `is_blocked` | `tests/rule_guards.lua` | `section("P1 同行已有别人 ⇒ 正式放置被拒")` … `P9 关卡关掉 one_per_row ⇒ 同行不拦`；断言文案 `"P1 同行第 4 格拒绝放 B"`、`"P1 拒绝后 (2,4) 仍是空的（没偷偷放进去）"`、`"P2 原因里点明是「列」冲突"`、`"P7 换人站在同一格 ⇒ 允许（目标格的旧人会离场）"`、`"P8 守卫只在交互层：存档/分享码恢复不被拦"` |
| 同上（手势层：长按=放置、双击=预放置、单击=笔记、长按后抑制尾随点击） | `tests/input_logic.lua` | `"长按时长与「已经玩了多久 / 棋盘多满」无关"`、`"越过门槛那一刻给一次反馈，且只给一次"`、`"兜底时钟与真实时间同速"`；日志 `★ 放置分辨：走的=【正式放置 hold_cell】` / `【预放置 pre_place】` |
| 同上（接线：`tap_cell`/`hold_cell` 打到数据层） | `tests/board_wiring_e2e.lua`、`tests/selftest.lua` | selftest：`"书桌所在格不可站人"`、`"拿起后「已正式放置」标记也清掉（否则该角色会被永久禁止打笔记）"`、`"正式放置把人挪到了新格（旧格已清）"` |
| 拿起/置灰还原（`do_clear` → `placed`） | `tests/gray_unplace.lua` | `★ 链路：拿起 ⇒ do_clear 清 core.placed`、`"拿起不改动选中（取消放置与选中已解耦 ✓）"` |
| **笔记**（`toggle_note`，经 `tap_cell` / `MODE_NOTE`） | `tests/rule_guards.lua` | `"B1 障碍物格拒绝铅笔笔记（place 模式的「选中后单击」路径）"`、`"B2 障碍物格拒绝铅笔笔记（MODE_NOTE 强制笔记路径）"`、`"B4 普通格打笔记照旧（对照组，防止一刀切）"`、`"X1 先有笔记，再打 ✗ ⇒ 笔记被擦掉"`、`"X2 先有 ✗，再打笔记 ⇒ ✗ 被擦掉"` |
| 笔记在棋盘上显示成字母 | `tests/cell_mark_letter.lua` | `★ tap_cell 要"先选中"才打标记` 那一段（14 条） |
| **X 标记**（`toggle_x` + 放置派生的"自动 ✗"） | `tests/rule_guards.lua` | `"X3 放置派生的自动 ✗ 也会擦掉同行同列的笔记"`、`"X4 撤销「打 ✗」⇒ 被它擦掉的笔记回来"`、`"X5 撤销「在 ✗ 上打笔记」⇒ ✗ 回来"`、`"X6 撤销一次放置 ⇒ 自动 ✗ 与被它擦掉的笔记一起还原"`、`"X8 存档往返：脏存档（同时有 ✗ 和笔记）被清洗成互斥"`、`"X9 分享码解码也守同一条不变量"`、`"B3 障碍物格仍然可以打/擦 ✗（旧行为保留）"` |
| X / 笔记 不变量（同一格不许两种都有） | `tests/rule_guards.lua` | `"R3 笔记 / ✗ 不计步：历史里仍只有 place/clear 这类真落子"`、`"R4 全盘不变量：随便点一通之后也不会有格子同时有 ✗ 与笔记"`、辅助 `view() 里不存在同时有 ✗ 和笔记的格子` |
| 撤销/重做、分享码、存档往返 | `tests/selftest.lua` | `"撤销后为空"`、`"重做后恢复"`、`"分享码可解回"`、`"摆位还原"`、`"笔记还原"`、`"X 还原"`、`"存档反序列化"` |

> 一句话：**改 `murdoku_core.lua` 的笔记/X/放置，`rule_guards.lua` 是最先该跑的那一套**（99 条、专为这三条规则写的）；
> 然后 `selftest.lua`（引擎语义）+ `input_logic.lua`（手势分流）+ `board_wiring_e2e.lua`（接线）。

---

## 8. 我跑了什么 / 推断了什么 / 没跑什么

### 8.1 实际执行（有日志文件，路径都在 `tools/_wip/`）
`tools/_wip/recon_full.log`（T1 全量）、`tools/_wip/suite_readme7.log`（README §2 的 7 套）、
`tools/_wip/handoff_block_check.log`（T2 全量、即 §3-B 那段命令的实跑）、`bundle_run.txt` / `bundle_out.txt`（打包前后 sha）、
`current.save.summary.json` / `current.save.warnings.txt`（转换报告）。
另跑了：`embed_script.mjs --probe`、`find_script.mjs`、`roundtrip.mjs`、`check_names.mjs`、`gil_to_save.mjs`（两次）、
`bump_build_marker.mjs --check`、自写探针 `tools/_wip/check_embedded.mjs`（取内嵌叶子算 sha/标记）。

### 8.2 推断（**没**直接执行，标出来供你判断）
- "`check_encoding` 的 13 项在 HEAD 上也是红的"——依据是这 13 个文件在 `git status` 里**都没出现**（= 已提交且未修改）。
- "`bump_build_marker` 在 HEAD 上也是红的"——这条**是实测**（用它的正则跑 `git show HEAD:…` 得 NULL），不算推断。
- "`current.save.json` 能被 `qxqy_studio_load` 接受"——依据是与已知可用存档同键集/同 format/schema，以及 `docs/` 里的历史实测记录。**不是**我这次的实测。
- "v278→v279 UI 没动"——**是实测**（两次转换的 tree/boxes/root 的 sha256 相同）。

### 8.3 没跑（及原因）
| 没跑 | 原因 |
|---|---|
| `qxqy_studio_load` / `qxqy_studio_play` | 会**替换当前会话的模拟器工程**，可能与 Lead / 其他 teammate 手上的试玩状态打架；这是 step 6 的事主战场，留给你 |
| `tools/sim/play_test.mjs`、`win_path.mjs`、`probe_*.mjs`、`geom_probe.mjs`、`audit_flow.mjs`、`audit_layout.mjs`、`verify_art.mjs` | 会**覆盖** `tools/sim/out/` 里既有的 `*.save.json` / `*.png` / `*.json` 产物，超出我这次的写权限（只允许 `current.save.json`）。它们依赖 `tools/sim/out/layout-plan.json`（由 `lua tools/dump_layout.lua` 生成）和插件 dist：`C:/Users/18182/.dsh/profiles/web/node_modules/dsh-plugin-beyond-simulator/dsh-plugin/dist/index.js`（存在，2026-09-25） |
| `check_all.ps1`（含 `-SkipSim`）整跑 | 它的 2e/2f/2h/6/7 步骤会**写仓库文件**（`tools/audit/*/sim-surface.json`、`docs/未验证清单.md`、`docs/搭建要求`、`docs/控件坐标表`、`tools/sim/out/layout-plan.json`）。我只跑了其中**只读**的那些步骤，其余按 §3-B 逐条替代。若要整跑请先接受它会重生成上述文档 |
| `node tools/gen_editor_guide.mjs`、`gen_setup_requirements.mjs`、`tools/audit/sim_surface.mjs`、`tools/audit/reconcile.mjs` | 同上（写 `docs/` / `tools/audit/`） |
| `tools/gil/check_assets.mjs --warn-only` | 只报告（素材待办），与本次改动无关，未纳入 |

---

## 9. 副作用 / 落盘清单（给 Lead 对账用）

| 路径 | 性质 |
|---|---|
| `qianxing-murdoku/records/recon-pipeline.md` | 本文件（允许的新产物） |
| `qianxing-murdoku/tools/sim/out/current.save.json` | 允许的新产物（1 562 995 B，sha `0AEB2E32…`） |
| `dist/client_script.lua` | **被 bundle 重写**：T1 时与跑前逐字节相同（`46299C85…`）；T2 因源码升到 v279 变为 `14034A28…`（1 295 427 B）。这是闸门要求的动作，不是我的改动 |
| `tools/lua-tooling/out/selene-report.txt` | ⚠️ **被我跑 `lua_lint.ps1` 重写**（该文件是 git 跟踪的，于是 `git status` 多了一条 ` M`）。内容就是本次 lint 报告。按指示我**没有** revert |
| `tools/_wip/*` | 我的临时件：`recon_run.ps1`、`handoff_block_check.ps1`、两个日志、`bundle_*.txt`、`layout-plan.json`、`check_embedded.mjs`、`current.save.{json,summary.json,warnings.txt}`、`dist_client_script_pre.bak.lua`（跑前备份）。**全部 UTF-8 无 BOM / 纯 ASCII**，已复查不污染 `check_encoding` |
| `tools/_wip/{base,out}_v279.gil` | **不是我造的**（teammate 的 v279 出货件，两者逐字节相同） |

**我确认没有动**：`lua/**`、`tests/**`、`存档/**`、任何既有 `*.save.json`、`tools/*.ps1`、`tools/gil/*`。
