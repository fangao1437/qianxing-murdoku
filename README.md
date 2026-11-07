# 千星奇域 · 2D 数独（murdoku）— 客户端 UI 工程

原神「千星奇域」UGC 的 **2D + Lua 客户端 UI** 工程：主页 / 选关 / 关卡内棋盘 / 线索卡 / 弹窗。
界面控件在编辑器里搭（`.gil` 存档），**逻辑全部在 Lua**（`lua/**`），打包成单文件 `dist/client_script.lua` 注入客户端。

---

## 1. 仓库里有什么

| 目录 | 内容 |
|---|---|
| `lua/` | 全部源码（入口、控制器、适配器、核心规则） |
| `dist/client_script.lua` | **打包产物**（注入客户端的那一份） |
| `versions/` | **版本梯子**：每一版的存档 + 打包产物 + 说明（回退用） |
| `*.gil` | 编辑器**存档**（界面控件树；`22x-…` 是最新几版） |
| `tools/` | 开发工具（见下） |
| `tests/` | **7 套回归**（改代码后必跑） |
| `docs/` | **实地调查 / 排障 / 设计文档**（含多次真机实测结论） |
| `assets/` | 素材与候选图 |

---

## 2. 怎么跑（三步）

```powershell
# 1) 语法 + 打包 + 回归（一道闸门，全绿才继续）
$lua = "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe"
& $lua tools/bundle_client_script.lua
foreach ($t in @("selftest","ui_math","entry_smoke","hide_safety","board_bg","effects_wiring","input_logic")) { & $lua "tests/$t.lua" }

# 2) 注入客户端（写进所有关卡的 external_lua_file）
powershell -ExecutionPolicy Bypass -File tools/install_script_to_sandbox.ps1
#    或双击 tools/sync-now.cmd

# 3) 真机验证：★ 必须【重启客户端】，只刷新页面不够；再进关卡
```

**判据**：日志第一行出现 `构建标记 v0xx` ⇒ 新包已加载。

> ⚠️ **每次导入 `.gil` 之后都要重跑一次同步** —— 导入会换关卡目录，旧同步对新关卡无效。

> 🔴 **`.gil` 里内嵌着一份脚本副本，导入时游戏用的是【那一份】**（2026-09-27 与 2026-10-09 各踩一次）
>
> - 实测：导入 `225` 后新关卡目录 `1073742018` 里出现的是 **`v075`**，
>   而当时最新已经是 **`v093`** ⇒ **日志首行是旧版**，看起来像新改动全没生效 ✗
> - ⇒ ★ **凡是准备交付/导入的 `.gil`，先跑一次 `embed_script.mjs` 把当前脚本嵌进去**：
>   ```powershell
>   $lua = "$env:LOCALAPPDATA\Programs\Lua\bin\lua.exe"
>   & $lua tools/bundle_client_script.lua                     # 先出最新包
>   node tools/gil/find_script.mjs <存档.gil>                  # 看里面嵌的是多大（可选）
>   node tools/gil/embed_script.mjs --in=<存档.gil> --out=<新存档.gil>
>   ```
>   **判据**：末尾必须打出 `✅ 内嵌脚本 == dist/client_script.lua（N 字节）` ✓
>   不通过就**别交付** ✓（`embed_script.mjs` 自检不过会 `exit 3`）
> - ⇒ 这样**导入即最新**，连第 2 步的手动同步都不需要（但重跑一次也无害 ✓）
>
> 🔎 **导入前还可以对一次名字账**（2026-10-09 起改成**分类报告** ✓）：
> ```powershell
> node tools/gil/check_names.mjs <存档.gil>            # 默认：只把"运行必须"的名字当判据
> node tools/gil/check_names.mjs <存档.gil> --strict    # 连"真缺"也算失败（补齐界面那一轮用）
> ```
> 它把"规划要、存档没有"的 281 个名字**分成三类** ✓：
> 🟢 **脚本会自动建**（14，白名单读自 `entry_client_script.lua`）·
> 🔵 **已被换代**（139，`clue.*` 被网格视窗取代）·
> 🔴 **真缺**（128，`select` 78 / `ruler` 15 / `room` 8 / `intro` 6 / `obj` 4 …）
> ⇒ ★ 旧版把三类混在一起 ⇒ **恒定 281、永远红** ⇒ 闸门失效 ✗ 现在只有 🔴 需要人管 ✓
>
> 🗄️ **同步脚本现在会【自动备份旧脚本】**（2026-10-09 起）：
> 覆盖前比 sha256，**内容不同就归档**成
> `_backup\sandbox-scripts\<关卡id>__<构建标记>__<时间>.lua` ✓
> —— 那是"**真机当时到底跑了哪一版**"的唯一证据，**已从 .gitignore 里放行、会入库** ✓
> （同内容则跳过，不会堆重复档 ✓）

---

## 3. 开发工具（`tools/`）

| 工具 | 用途 |
|---|---|
| `bundle_client_script.lua` | 把 `lua/**` 打成单文件 `dist/client_script.lua` |
| `install_script_to_sandbox.ps1` / `sync-now.cmd` | 注入客户端（多 root 同步 + 字节核对） |
| `gil/gilread.mjs` | **`.gil` 读写库**（`readGil` → `{recs,byName,tree,pack}`；保存配方 `encodeMsg` + `pack(body)`） |
| `gil/set_key_art*.mjs` | 给弹窗四键写胶囊底图（`imageId` + **素材库哨兵**） |
| `gil/fix_palette_ids.mjs` | 修 `portrait.*` 的图片 id |
| `qx/**` | 头像素材识别、运行时探针（只读） |
| `sim/**` | UI 模拟器相关的分析与产出 |

**离线依赖**：`tools/bin/{stylua,selene}`（格式化/静态检查，可自备，未入库）。

---

## 4. 外部依赖与调用地址

| 项 | 地址 / 标识 |
|---|---|
| 目标平台 | 原神「千星奇域」UGC（2D 客户端控件 + Lua 客户端脚本） |
| 本机 Lua | `%LOCALAPPDATA%\Programs\Lua\bin\lua.exe` / `luac.exe` |
| 客户端存档根 | `%USERPROFILE%\AppData\LocalLow\miHoYo\原神\BeyondLocal\<UID>\Beyond_Local_Save_Level\<关卡id>\external_lua_file\client_script.lua` |
| git | `C:\Users\18182\AppData\Local\Programs\ds-harness-desktop\runtime\git\cmd\git.exe` |
| 官方文档缓存 | `docs/api-cache/*.txt`（客户端控件 / Lua API / 界面控件组等） |
| 参考站点（布局灵感） | `murdoku.com/play/` |
| 素材库素材（示例） | 弹窗胶囊 `107179`（760×152 米白）· 头像 `112042 / 105104 / 112031 / 105105` |

---

## 5. 当前状态（摘要，详见 `PLAN.md`）

- ✅ 主页 / 选关 / 关卡内棋盘 / 线索卡（网格视窗）/ 灰白层 / 笔记载体 均已实机可用
- ✅ 弹窗（四键）**能显示、能点、三个事件都通**
- ⏳ 弹窗四键的**运行时贴图**未完成（只差一处读数）
- ⏳ `assets` 内容区（`row.*`、`portrait.*`）运行时取用未打通
- 📄 排障与实测结论集中在 `docs/`（建议先读 `docs/弹窗-线索汇总.md`、`docs/assets取不到-追查.md`）
---

## 存档位置（★ 2026-10-18 起 ✓）

★ 根目录的 \.gil\ 存档**已全部移入 **\存档/\\** ✓**（★ 90 个 ✓ 全部 ≥v237 ✓）

★★ **原因** ✓：★ 根目录散落文件太多 ✓ ⇒ ★ 按类别归位 ✓
　 ★ **不是**按"30 版"归档 ✗ —— ★ **旧档（≤v236）在 **\qianxing-murdoku-old\** 仓 ✓**

★ **工具用法不变** ✓：★ 既有工具都【显式传 .gil 路径】✓
`ash
node tools/gil/inspect_gil.mjs "存档/455-外圈骑格线-v267.gil"
node tools/gil/embed_script.mjs --in="存档/452-门定位常走路径.gil" --out="存档/456-新档.gil"
`
★ ⚠️ **不传参时的默认值仍指向根目录** ✗ ⇒ ★ **请始终显式传路径** ✓
