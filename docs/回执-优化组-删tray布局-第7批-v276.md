# 回执 —— 优化组：第 7 批（删 `apply_tray_layout` 187 行 + 按钮上色换入口）+ v276 交付

> 日期：2026-10-18 ｜ 构建标记 **v276** ｜ 交付 **`存档/464-删tray布局-v276.gil`**（1,616,752 B）
> 基线：`存档/463-清空未实现族-v275.gil`
> 台账：`docs/审计-脚本必要性/清理进度.md`

---

## 一 本批做了什么（一件"删"＋一件"接"）

| 动作 | 内容 |
|---|---|
| **删** | `Adapter:apply_tray_layout` **整段 187 行**（头像卡重排：容器查找 + per-row 计算 + 卡片/子控件几何 + 头像卡体检 + 按钮上色块） |
| **接** | 其中**唯一还活着**的是「按钮底图上色」（**缺陷 1** 修的就是它的开关）⇒ 提成独立入口 **`Adapter:apply_btn_art()`**，由 `main.lua` 在设好 `cfg.btn_list` 之后调一次 |
| 同步 | `tests/btn_art_gate.lua`（缺陷 1 的回归）调用点改成 `apply_btn_art()`；`tests/perframe_throttle.lua` 的"守卫型方法必须存在"名单：`apply_tray_layout` → **`apply_btn_art`** |

### 判据（三条都要成立才删）

1. 头像卡容器 `tray` 已在第 6 批按用户指令从布局计划删除，`Controller:tray_layout_canvas` 同批删除
   ⇒ **全仓没有任何调用点**；
2. 它每局唯一能干的事就是打一行「找不到头像卡容器（cfg.tray_parent，默认 tray）」；
3. 真机日志（v274）逐条核对：那行每局都在，除此之外它一无所出。

### 新入口的形状（把缺陷 1 的约束**原样保留**）

```lua
function Adapter:apply_btn_art()
  if self.cfg.btn_art ~= true or print == nil then return 0 end   -- ★ 默认关闭，opt-in
  local names = self.cfg.btn_list or {}
  local done, miss = 0, 0
  return self:_tray_btn_art(0, names, done, miss)
end
```

`_tray_btn_art` **一字未动**（缺陷 1 的判据 `_tray_btn_art(moved` 仍只出现 1 次）。

---

## 二 验收读数

| 闸门 | 读数 |
|---|---|
| 两个 lua 文件 `loadfile` | ✅ OK / OK |
| `check_nesting.mjs` | ✅ `[嵌套] 0 / [节流嵌套] 0 / 深度不平衡 0` |
| **`lua53check dist --run`** | ✅ `LOAD OK` + `RUN OK`（892,116 字符 / 21,279 行） |
| **`lua_quote_scan`** | ✅ 20,658 行全部干净 |
| **全量离线回归** | ✅ **35 套 / 0 失败** |
| **`btn_art_gate`（缺陷 1 回归）** | ✅ **11 通过 / 0 失败** —— 换入口后行为不变（默认关、打开后仍会重设） |
| `perframe_throttle`（结构哨兵） | ✅ 11 通过 / 0 失败（名单已换成 `apply_btn_art`） |
| `check_names` 🔴 真缺 | ✅ **0**（保持） |
| `dist/client_script.lua` | 1,324,663 → **1,314,124 B** |
| 交付存档 | **`存档/464-删tray布局-v276.gil`** ｜ 内嵌脚本 = dist（SHA256 相同） |
| `roundtrip` / `dupids` / 内嵌脚本独立编译 | ✅ 逐字节一致 / 0 / `LOAD OK`+`RUN OK` |

**行数**：`engine_adapter_qianxing` 6,235 → **6,064**（−171 净）｜`main.lua` 2,354 → **2,357**（＋3，新增一次调用）

---

## 三 预期真机变化（导入 `464` 后）

- 首行 `构建标记 v276 …`；
- **不应**再有「找不到头像卡容器」那行 —— 本批之后这个函数已经不存在了；
- 「上色名单（来自规划）：N 个按钮」仍在（那是 `main` 里设 `cfg.btn_list` 的日志），
  但**不会**出现「--- 按钮底图上色（运行时）---」块（`cfg.btn_art` 默认 nil ⇒ 闸门关着）✓
- 界面**零可见变化**（删的全是无人调用的路径）。

---

## 四 剩下的（台账已更新）

| 内容 | 规模 | 前置 |
|---|---|---|
| `diagnose_cell` + `diagnose_template` | ≈310 行 | 要连 `perframe_throttle` 的名单 + `main.lua` 两处调用 + `entry` 的 `cfg.diagnose_cell` 一起改；v274 日志已证明两者全绿（结案证据齐了） |
| `Adapter:enforce_screen_layers` | 100+ 行 | 审计定 P3：注释写着"随时可以再开"的层序实验 ⇒ **等用户拍板** |
| E 类数据：线索类型 60 → 9、`view` 死字段、`cfg` 43 条死配置 | ≈600 行 / 23 KB | 线索类型要用户定（内容设计还会不会加新类型） |
| 注释剥离 | **−876 KB（−65 %）** | 用户已定：代码收尾后再做 |
