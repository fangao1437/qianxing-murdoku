# 本轮计划 —— 头像专用层 `portrait`（家具不再盖住放置的头像）· v283（2026-10-20）

> 基线 = 最新版 **v282**（`存档/470-遗留清理-v282.gil`）。
> 交付：★ **`472-头像层-v283.gil`**（1,617,307 B / **371** 条 / 内嵌 **v283**，工程根目录）
> 回执：`docs/回执-头像层-v283.md`

## 一、本轮定位

| 项 | 值 |
|---|---|
| 当前步骤 | **7（真机反馈）→ 5（实现）→ 6（离线回归）** |
| 用户原话 | 「查看最新版本，基于最新版处理一个几何问题，**现在家具图层会盖在放置的头像上，把这个问题解决**」 |
| 根因 | 头像走 `image` 落在 **face（最底）**，家具 `obj` 在它上面；`face` 是不透明色板 ⇒ 不能对调 |
| 改法 | 模板补 **`portrait`** 层（obj 之上、wall 之下），头像改画那一层；`tint` 一律房间色 |
| 不做 | 不动门墙/家具/叉/笔记的层与画法；不动玩法规则 |

## 二、进入证据

| # | 事实 | 依据 | 标签 |
|---|---|---|---|
| 1 | 层序（旧）：face → hint → **obj** → wall → door → x → note；头像走 `image` → face | `lua/entry_client_script.lua` 的 `layer_order` + `image` 分支 | `[实测]` |
| 2 | 家具 `obj` 由 `_paint_obj` 画（v281 起每帧重放），一定在 face 之上 | `Adapter:_paint_obj` + `_repaint_cell_overlays` | `[实测]` |
| 3 | 模板 content 现有 13 个子控件（无头像专用层） | `tools/gil/_probe_cell_layers.mjs 470` | `[实测]` |
| 4 | 2026-10-16 的"有棋子时下发白色"是因为头像与房间色同控件（`imageColor` 乘算） | `ui_controller.lua` 那段长注释 | `[实测]` |

## 三、改了什么

| 类别 | 改动 |
|---|---|
| 存档 | 模板两份 content 各补 `portrait`（克隆 `face`；id 1073743800/3801）；工具 `tools/gil/gen_portrait_layer.mjs` |
| 配置 | `layer_order` 插入 `"portrait"`（obj → **portrait** → wall） |
| 适配层 | 新增 `_paint_portrait`；`image` 对 `cell.*` 改画 portrait（`_portrait_want` + 重放③）；贴格名单加 portrait |
| 界面层 | 格子 `tint` 一律房间色（撤掉白色权宜修法） |
| 测试 | 新增 `tests/portrait_layer.lua`（12 条，含旧适配器 Red）；`card_fit_gate` ③ 判据换成 portrait（10/0） |

## 四、退出证据

| # | 判据 | 结果 |
|---|---|---|
| 1 | 语法 | ✅ 3 个 Lua 文件编译通过 |
| 2 | 有效 Red | ✅ 旧适配器跑同一套：头像仍在 face、portrait 未亮（3 条红） |
| 3 | Green | ✅ `portrait_layer` 12/0；`card_fit_gate` 10/0 |
| 4 | 全量离线 | ✅ **40 套 0 失败** |
| 5 | 存档 | ✅ 371 条（+2），两份 content 都有 portrait 且登记；`roundtrip` 逐字节一致 |
| 6 | 版本链 | ✅ 与 471 差异恰好 1 处；内嵌标记 v283 |
| 7 | 真机 | ★ 待导入 `472` |

## 五、下一步

1. **真机**：有家具的格子上放一枚棋子 ⇒ 头像在家具之上、房间色仍在；拿走 ⇒ 头像消失；打叉仍红叉。
2. 若报"GUID 重复"（新增控件的老风险）：`tools/gil/remap_ids.mjs` 把 1073743800/3801 再挪一档。
3. 若真机看到"白板闪一下"：把存档里 portrait 的初始 `visible` 置 false（脚本第一帧也会关它）。