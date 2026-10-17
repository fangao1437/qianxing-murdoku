# 回执 —— 提示层归编辑器 · 障碍物 `things` · 门墙接线（v255 / 2026-10-17 晚）

> 基线：★ **`395.gil`**（用户 12:30 导出）　交付：★ **`397-线索提示-things-门墙-v255.gil`**
> 上一轮（线索位置提示 v254，颜色染 `face`）见 `docs/回执-线索卡位置提示-2026-10-17.md`；本轮是它的**收口**。

---

## 〇 一句话结论

| 项 | 结果 |
|---|---|
| 「模板已经修改了、颜色也调好了」= 用户加的 **`hint` 提示层** | ✅ 已查到：`cell → content → hint`（135×135，`imageColor = 0x7F0063D5` = 50% 透明蓝） |
| 脚本只"管显示" | ✅ 新增 `set_property("hint")`：**只开关可见性**，颜色一个字不写；旧的 `HINT_TINT` 常量**已删** |
| 障碍物单独一个 `things` 区 | ✅ 新建成：`root → things`（画布外）＋ 6 个素材槽 `things/obj.{table,plant,carpet,chair,shelf,statue}` |
| 障碍物怎么画到格子上 | ✅ 补了 `cell → content → obj`（第 2 位），适配层从 `things` 调色板**照抄图与色** |
| 门墙渲染 | ✅ 模板里 `wall.*/door.*` 本来就有 ⇒ `walls/doors` 四向布尔 → `_apply_edges` 开关它们（本轮离线钉住） |
| 导出新存档 | ✅ **`397-线索提示-things-门墙-v255.gil`**（1,621,093 B / 354 条记录 / 内嵌 **v255**） |

---

## 一 先查清 `395.gil` 里你到底改了什么（不猜）

| # | 事实 | 怎么查的 |
|---|---|---|
| 1 | 相对 394 只多了 **2 条记录，名字都叫 `hint`**（父 = `content`，135×135） | `node tools/gil/_probe_diffnames.mjs 394.gil 395.gil` |
| 2 | `hint` 的 `imageColor = 2130731989 = 0x7F0063D5`（**50% 透明蓝**）、`imageId = 100001` | `node tools/gil/img_block.mjs 395.gil hint` ＋ 转存后读字段 |
| 3 | `content` 下已有 `face / hint / x / wall.{up,down,left,right} / note / door.{up,down,left,right}`，**唯独没有 `obj`** | `node tools/gil/_probe_kids.mjs 395.gil content` |
| 4 | `assets` 里只有 16 个 `row.*`，**没有 `portrait.*`** | `node tools/gil/list_names.mjs 395.gil portrait` |
| 5 | 存档里没有 `things` | 同上（命中 0） |

★ 结论：你说的"模板改了、颜色调好了"就是 **`hint` 这一层** ✓；
　 家具**没有可画的图层**（缺 `obj`）、也没有素材区（缺 `things`）⇒ 这两样是本轮补的。

---

## 二 存档怎么改的（两个工具，都有自我断言）

| 步 | 命令 | 做了什么 | 断言 |
|---|---|---|---|
| ① | `node tools/gil/gen_things_obj.mjs --in=395.gil --out=396-things.gil` | `root → things`（200000,200000，900×180）＋ 6 个素材槽（135×135，色块占位）＋ `content/obj`（插在 `hint` 之后 = 第 2 位） | 记录 346→354；`things` 父 = root、6 个子控件都已登记；`content` 第 2 位 = `obj`；重读磁盘 + 往返逐字节一致 |
| ② | `node tools/gil/embed_script.mjs --in=396-things.gil --out=397-…-v255.gil --expect-marker=v255` | 内嵌 v255 脚本（1,310,397 → 1,329,944 字节） | **字段级 diff 恰好 1 处**（只有脚本叶子）+ 版本标记 = v255 |

★ 图层顺序（索引大的画在上面）：`face(0) < hint(1) < obj(2) < x / wall.* / note / door.*`
　 ⇒ 提示底色在**家具图标之下**（图标不被蓝色盖住），门墙仍压在格子边缘 ✓
★ `things` 摆在**画布外**（和 `tpl-container` 同一套路）⇒ 不会出现在画面上 ✓

**`things` 现在长这样**（占位色块；真图请在编辑器里换，**名字别改**）：

| 控件名 | 代表 | 占位色 | 能不能站人 |
|---|---|---|---|
| `things/obj.table` | 桌子 | `0xFFB07946` | 不能 |
| `things/obj.plant` | 植物 | `0xFF4CAF50` | 不能 |
| `things/obj.carpet` | 地毯 | `0xFFD9C8A6` | 能 |
| `things/obj.chair` | 椅子 | `0xFFE0A040` | 能 |
| `things/obj.shelf` | 书架 | `0xFF7A5230` | 不能 |
| `things/obj.statue` | 雕塑 | `0xFFB8B8C0` | 不能 |

---

## 三 脚本改了什么

| 文件 | 改动 |
|---|---|
| `lua/ui_controller.lua` | ① 删 `HINT_TINT`（颜色归编辑器）② 格子节点下发 **`hint = true/false`（每格都发）** ③ `tint` 回到只管房间色 |
| `lua/engine_adapter_qianxing.lua` | ① 新分支 `key == "hint"`：`sub(cell,"hint")`（穿透 `content`）→ `SetVisible`，**不写颜色**；老存档没有这一层时**静默算送达** ② `read_palette()` 同时扫 `assets` 与 **`things`**，并读 `imageColor` ③ `object` 分支把调色板的**颜色**也照抄到 `cell.obj` |
| `lua/entry_client_script.lua` | 构建标记 → **v255 / 2026-10-17**（日志第一行就能看出导入的是哪版） |
| `tools/sim/kit.mjs` | 模拟器建树补齐 `hint` / `wall.*` / `door.*` / `things`（**与 397 存档逐项同构** —— 这条纪律是被"模拟器测不到真机的东西"反复咬出来的） |
| `tests/clue_hint.lua` | 第 5 节改为断言布尔 `hint`（并对**反向**断言 `tint` 与提示无关） |
| `tests/things_wiring.lua` | ★ 新增 30 条：穿透 `content` 找子控件 / 只开关不改色 / 调色板读图+色并照抄 / 门墙四向开关 |

---

## 四 证据

| # | 判据 | 结果 |
|---|---|---|
| 1 | 新存档往返一致 | ✅ `node tools/gil/roundtrip.mjs 397-…v255.gil`：重编码与原始体**逐字节完全一致** |
| 2 | 脚本运行必须的名字全在 | ✅ `node tools/gil/check_names.mjs 397-…v255.gil`：对账通过（含 `wall.*` / `door.*`） |
| 3 | 内嵌脚本版本 | ✅ `embed_script` 断言「版本标记 = v255」「字段差异恰好 1 处」 |
| 4 | 离线回归 | ✅ **32 套 `tests/*.lua` 全绿**（`clue_hint` 89 / `things_wiring` 30） |
| 5 | 模拟器（试玩 Worker） | 见 §五（读数：`obj` 颜色来自 `things`、`hint` 只开关、门墙可见性） |

---

## 五 模拟器读数（`runtime=simulator`）

★ 为什么不用"把 `.gil` 转成模拟器存档"：转存**丢脚本挂载**（运行时没有脚本，什么都不动），
　 而且模拟器**不实例化模板格子**（整块棋盘只剩 `cell.1.1`）✗
⇒ 走 `layout-plan` 建树（`tools/sim/kit.mjs` 已把 `hint` / `wall.*` / `door.*` / `things`
　 **按 397 存档逐项补齐**），脚本内联挂载 ⇒ 整块棋盘 + 脚本在跑 ✓

命令：`node tools/sim/build_hint_save.mjs` → `node tools/sim/things_hint_probe.mjs`

| 读数 | 第一关 `cell.1.1` | 第二关 `cell.1.1` |
|---|---|---|
| `obj` | visible=**true**，`imageColor = 0xFFB07946`（= `things/obj.table` 桌子） | visible=**true**，`imageColor = 0xFFE0A040`（= `things/obj.chair` 椅子） |
| `wall.up` / `wall.left` | visible=**true**（(1,1) 是左上角 ⇒ 两条边都是墙） | — |
| `hint` 没选中 | visible=**false** | visible=**false** |
| `hint` 选中 B（= 卡 2：两人坐在椅子上 ⇒ 高亮两把椅子） | — | visible=**true**（`cell.1.1` 是椅子） |
| 再点一次取消 | — | visible=**false** |
| `hint` 的颜色 | `0x7F0063D5` **一次都没被脚本改过** ✓ | 同左 |

判定：**9 / 9 通过**；截图 `tools/sim/out/things-1-case001.png` / `things-2-hint-on.png` /
`things-3-hint-off.png`；过程日志 `tools/sim/out/things.log.txt`。

★ 这证明的是**接线通**（图层开关 / 调色板照抄 / 门墙四向）✓，**不是**美术观感 —— 后者只能真机看。

---

## 六 真机核验清单

| # | 项目 | 怎么看 | 判据 |
|---|---|---|---|
| 1 | **半透明蓝提示层** | 点线索卡 | 棋盘上对应格出现蓝色半透明底，**家具图标/字母仍然看得清** |
| 2 | **家具图标** | 进第一关 | 桌子/植物/地毯/椅子各就各位（现在是色块占位） |
| 3 | **门与墙** | 看两关的房间边界 | 第一关 3 个区域、第二关 4 个区域；第二关**只有一扇门** |
| 4 | **人像不被染** | 选一个人放到格子上 | 头像保持原色（这一轮不再染 `face` ✓） |
| 5 | 换真素材 | 把 `things/obj.*` 的图换掉后重新导入 | 棋盘上的家具跟着变（脚本不用改） |

---

## 七 待你拍板 / 要做的一件事

1. **换美术**：`things/obj.{table,plant,carpet,chair,shelf,statue}` 这 6 个控件的图，
   在编辑器里换成真家具素材（**控件名一个字符都不要改**，脚本按名字取）。
2. 若真机看下来**提示层太蓝/太浅**：直接在编辑器里改 `hint` 的填充色即可（脚本不碰颜色）。
3. 若家具图标**太大/太小**：改格子模板里 `obj` 的尺寸即可（脚本只换图，不动尺寸）。
4. **门/墙的颜色现在来自模板**（`content/wall.*` = `0xFF3310A0` 紫、`content/door.*` = `0xFFD6DE1A` 黄绿），
   脚本**一个颜色都不写** ✓。要贴着设计图那种"深墙 + 橙门"，在编辑器里改这两个子控件的填充色即可；
   若连形状也不对，说一声，我把墙体/门做成 `things` 里的素材槽（`thing.wall` / `thing.door`）走同一套调色板。
