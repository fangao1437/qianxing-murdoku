# 回执 —— 去掉 `things` 素材区，家具素材改走脚本（v258 / 2026-10-18）

> 用户定位（关键判据）：「**错误是从 396 就存在的**，只是首次试玩会不触发报错」「**395 是没错的**」
> ⇒ 结论方向明确：**396 是我第一次在存档里新建控件**（`things` 素材区 7 个 + `content/obj` 2 个）的那一版。

## 〇 做什么

| 项 | 处理 |
|---|---|
| `things` 素材区（7 个新控件：`things` + `obj.table/plant/carpet/chair/shelf/statue`） | ★ **整块删掉**（`delete_controls --names=things`，级联删 6 个子控件） |
| 家具/障碍物素材 | ★ **改由脚本提供**：`cfg.obj_art = { table = { id=100001, color=0xFFB07946 }, … }` |
| `content/obj`（格子里的家具图层，2 条） | **保留** —— 不给格子一个图层，家具就画不出来（这条在模板里，不在画布上） |
| 其余（门墙配色/拉伸、贴格、选关闸门、第二关两扇门） | 与 v257 相同 |

★ 依据：家具图标只需要「**一张图 + 一个颜色**」 ⇒ 放脚本配置就够，**不必新建控件** ✓
★ 优先级：编辑器里若真有 `things`/`assets` 下的同名控件，**仍以控件为准**（`read_palette`：控件先扫、配置补缺）✓

## 一 产物（= v258）

```
node tools/gil/delete_controls.mjs --gil=402-高段GUID-v257.gil --out=403-去things-v258底.gil --names=things
node tools/gil/embed_script.mjs --in=403-去things-v258底.gil --out=403-去things-脚本素材-v258.gil --expect-marker=v258
```

| 检查 | 结果 |
|---|---|
| 记录数 | 375 → **368**（删 7 条） |
| 档内重复 GUID | ✅ **0** |
| 名字对账 `check_names` | ✅ 通过（`things`/`obj.*` 转成"本期不做"，脚本对缺失的素材容器**静默跳过**）|
| 往返 `roundtrip` | ✅ 逐字节一致 |
| 内嵌脚本 | ✅ 标记 = **v258**（「去掉 things 素材区 + 家具素材走 cfg.obj_art」）|
| 离线回归 | ✅ **32 套全绿**（`things_wiring` 43 条：新增 4 条"没有素材控件时 cfg.obj_art 仍提供 obj.chair"）|
| 模拟器 | ✅ **12/12**（家具色 = 0xFFB07946 / 0xFFE0A040 来自 `cfg.obj_art`；贴格 108 / 91）|

## 二 导入注意

1. **先删掉工程里残留的 `things`**（396~402 那几次导入可能已把它建进工程）——
   路径：左侧「界面控件」树里找 `things`（下面挂着 `obj.table` 等 6 个）→ 删掉整块。
2. 或者直接**新建空白工程**再导入 `403`。
3. 之后再试玩：应当**不再报**「开关控件GUID重复」。
4. 若还报同一个号，把报错截图给我 —— 下一步我会把 `content/obj` 那 2 条也去掉
   （代价：家具图标先不画，其它三条修复照常生效）。

## 三 家具素材想换真图

改 `lua/entry_client_script.lua` 的 `cfg.obj_art`：

```lua
obj_art = {
  table  = { id = 100001, color = 0xFFB07946 },   -- 把 id 换成编辑器素材库里的图即可
  ...
}
```

★ 不动存档、不动控件 ✓（要用「需要拉伸」的素材时，把 `id` 换成底板类 `106053` 更稳）

## 四 工具

| 文件 | 说明 |
|---|---|
| `tools/gil/delete_controls.mjs`（已有）| 级联删控件，自带"悬空子/父指针"自检 ✓ |
| `tools/gil/renumber_ids.mjs`（上一轮新增）| 改 GUID 用（本轮不再需要，但留着）|
| `tools/gil/_probe_dupids.mjs` 等五件套 | 撞号排查 |
