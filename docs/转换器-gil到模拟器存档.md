# `.gil` → `qxqy-simulator-save` 转换器（证据报告）

> 建档：2026-10-15 夜 ｜ 作者：AI（任务：把 v240 交付档搬进模拟器做真机前试玩）
> 交付物：`tools/sim/gil_to_save.mjs`（新）· `tools/sim/out/371-v240.save.json`（转换产物）· 本文件（新）
> ⚠️ 本次**没有改动任何既有文件**（`.gil` / `gilread.mjs` / `sim-save/*.save.json` / `lua/*` / `dist/*` 全部只读）。

---

## 〇 一句话结论

★ **换算器成立、产物可加载、试玩能起来** ✓ —— 读数见 §3；
★ 但**必须记住一条**：`371-结算按钮-v240.gil` 里的控件几何**混着两套口径**（编辑器原生「父相对」＋ 你自己脚本写的「1920 设计空间原值」），
换算器**逐条判定**并**逐条 WARN**（§5），`home.*` / `hud.progress` 这 6 条是设计空间原值。

> ★★★★ **2026-10-15 深夜追记：本报告的 §3 读数直接判掉了一个错误假设** ✗✓✓
>
> ★ 我曾按"设计空间 (960,404) ÷ 5/6 − 画布中心"推出 `home.select` 应是 `offset(160,−46)` ✗
> ★★ 本报告用**照抄插件公式**重算 1001 个盒、与参考档**0 处不符** ✓ ⇒ ★ **那套口径不成立** ✓
> ★ 而且**两套口径的差正好解释了真机的一个怪现象** ✓：
> 　· `gen_home.mjs` 把**设计空间原值**直接写进位置对 ✗（`home.title/select/continue/shop/bag` ＋ `hud.progress` 共 6 条 ✓）
> 　· `add_button.mjs`（＝当初加 `settle.btn` 的那条路 ✓）走「**画布空间、相对根中心**」✓
> 　⇒ ★★ 同一个 `root` 底下**混着两套坐标系** ✓ —— ★ 这正是"照文档算出来的位置与引擎实际表现对不上"的温床 ✓
> ⇒ ★ 结论（本项目已写进 `main.lua` ✓）：★ **位置不许信存档** ✓ ——
> 　★ `settle.btn` 自 **v242** 起改由脚本**每帧显式 `SetSizeDelta` ＋ `SetAnchoredPosition`** ✓
> 　★ 本报告 §3 量到的 `settle.btn` box **(158.00, 79.60) 217×60** ✓ 与那两条写入值
> 　　（`217×60` / `(-642,-380)` ⇒ 画布中心 (158, 70) ＋ `root` 自带 `+9.6` 偏移 = **79.6** ✓）**逐位吻合** ✓✓
> 　　⇒ ★ **脚本写的几何是对的** ✓ ⇒ ★ 剩下的可疑项就只剩**它在父级里的层序**了 ✓（见 `docs/删除旧方块与结算按钮.md` ✓）

---

## 一 交付物与复现命令

| 项 | 值 |
|---|---|
| 换算器 | `tools/sim/gil_to_save.mjs`（复用 `tools/gil/gilread.mjs`，**没有第二套 protobuf 实现**） |
| 产物 | `tools/sim/out/371-v240.save.json` ｜ 1,456,372 B ｜ sha256 `071AC714FA60829E1E226C119EA0534A1B4154E0ED9C3A68811E1E48C951D4AE` |
| 输入 | `371-结算按钮-v240.gil` ｜ 1,551,321 B ｜ sha256 `D2E266CCAD85492A1AD3DB050012F54EF544EFE5ABA7061447824EAC57C9113E`（＝ v240 文档里那颗 ✓） |
| WARN 全量 | `tools/sim/out/371-v240.save.warnings.txt`（含每条明细） |
| 汇总 / 对账 | `tools/sim/out/371-v240.save.summary.json`（含 `--check` 结果与逐条口径判定的**理由行**） |

```powershell
cd D:\新建文件夹\miHoYo Launcher\qianxing-murdoku

# ① 转换（默认 --geom=auto，逐条判口径）
node tools/sim/gil_to_save.mjs --in="371-结算按钮-v240.gil" --out="tools/sim/out/371-v240.save.json"

# ② 转换 + 与参考存档交叉核对（同时自检盒算法）
node tools/sim/gil_to_save.mjs --in="371-结算按钮-v240.gil" --out="tools/sim/out/371-v240.save.json" `
     --check="sim-save/murdoku-v215-测试存档.save.json"

# ③ 其它口径（诊断用，不是默认）
#    --geom=canvas  全部按「画布绝对坐标（中心 − 800,450）」读（＝任务书假设的那套）
#    --geom=design  全部按「1920×1080 设计空间原值」读
```

会话里加载（本次实测用的就是这条）：

```
qxqy_studio_load { "path": "qianxing-murdoku/tools/sim/out/371-v240.save.json" }
```

---

## 二 `.gil` 的真实结构（为什么这个换算器站得住）

| 层 | 事实 | 证据 |
|---|---|---|
| 信封 | 20 B 头（`[总长,1,806,2,载荷长]`）+ 体 + 4 B 尾；**不是** GIA 的 `Root`（GIA 头的第 3 个 u32 是 `3`，本档是 `2`） | 插件 worker.js 里 `Be=20, mr=806, pr=1657` 与 GIA 头校验；本档头 `1551317,1,806,2,1551297` |
| 组 | 顶层 `#9` ＝ 整组：`#501` = **37 个根 id**、`#502` × 365 = **扁平记录表**、`#503` = 1 | `tools/sim/out/_gil_g9.mjs` 实测 |
| 记录 | 表里每条 = 插件的 `ContentWrapper`：`#501 guid / #502 info[] / #503 children / #504 parent / #505 data[]` | 与 worker.js 内嵌 proto 逐字段同名同号（见 §4） |
| 类型串 | 记录里**没有**「预设按钮/图片…」这类类型串（本档只有 1 条 `客户端控件容器`）⇒ 类型只能按 **Details 槽位**判 | 类型直方图：`(none):344  客户端控件容器:1` |
| 引擎块 | `#9/#502` 里有 20 条**引擎自带**脚手架（`默认布局` + 小地图/技能区/摇杆… + 5 个 `*HierarchyRoot`），guid 段 `1073741825…1073741844`（全在 `客户端控件容器`=`1073741845` 之前）⇒ **剔除**（参考存档里也没有它们） | `_gil_roots.mjs`；参考存档按名查：`默认布局/小地图/技能区/*HierarchyRoot` 全部 **false** |

⇒ 剔除引擎块后 **345 条用户控件 + `客户端控件容器` 记录 = 345**，与 `gilread.recs` 的 345 **逐条对齐** ✓。

---

## 三 验证结果（模拟器实测读数）

### 3.1 加载 ✓

`qxqy_studio_load { path: "qianxing-murdoku/tools/sim/out/371-v240.save.json" }`

```json
{ "warnings": [], "metadata": {},
  "snapshot": { "layoutSchemaVersion": 2, "version": 1, "canvasId": "pc-16-9",
                "canvas": { "width": 1600, "height": 900, "presets": [5 条] },
                "tree": [345 行], "storage": { "path": "qianxing-murdoku/tools/sim/out/371-v240.save.json" } } }
```

★ `warnings: []` ⇒ 插件的归一化（`Xe()` + 迁移 `$r()`）**没有报任何问题** ✓（它只吃 `layoutSchemaVersion / meta / canvasId / version / selectedId / root`；`tree/boxes/inspector` 是 `get` 时**重算**的派生字段 —— worker.js `Br()`+`te()`）。

### 3.2 控件数 & 几何（从插件自己回读的快照里数出来）

| 项 | 回读值 |
|---|---|
| `tree` 行数 | **345**（distinct guid 也 345）＝ `.gil` 记录数 345 ✓ |
| `sc1` → `root` | `sc1`(guid 1073741845, 客户端控件容器) → `n128` `root`(guid 1073741846, 127 个孩子) |
| `settle.btn` | `n363` guid 1073742775，**子控件 = `bg`(n364) + `label`(n365)** ✓，box = **(158, 79.6) 217 × 60** ⇒ 左边缘 49.5、下边缘 49.6（＝设计空间 `x=60, y=960, 260×72` 换算到画布 `50…266.7 / 40…100` ✓✓ 与 `docs/删旧方块与结算按钮-v240.md` §1.2 的设计几何**吻合**） |
| `home.select` | `n188` guid 1073742118，box = **(800, 563.33) 383.33 × 73.33**，`KEYBOARD.offset = {x:0,y:113.33}` |
| `home.title` | `n187` box = **(800, 737.5) 833.33 × 91.67** |
| `home.continue/shop/bag` | (800, 463.33) / (800, 363.33) / (800, 263.33)，均 383.33 × 73.33（纵向等距 100 ✓） |
| `select.card.1…4` | `n144`(1073742733)/(n143)/(n142)/(n141)，box 中心 x = **338 / 646 / 954 / 1263**，均 **258 × 360**（y = 454.6）⇒ 四张卡居中一排 ✓ |
| `hit.select.card.1` | `n158` box 与 `select.card.1` **完全重合**（338, 454.6 / 258 × 360）✓ |
| `select.back` | `n147` box = **(76, 843.6) 52 × 52** ⇒ 左边缘 50 ＝ 设计 `x=60` ✓ |
| `select.prev` / `select.next` | (76, 459.6) / (1524, 459.6)，52 × 52 ✓ 左右对称 |
| `select.page` / `select.title` | (800, 87.6) 108 × 58 ／ (800, 805.6) 833 × 75（底/顶居中）✓ |
| `tpl-container` `topbar` `right` `hud.progress` | (800, 459.6) 150×150 ／ (800, 866.6) 1600×87 ／ (1375, 436.6) 383×733 ／ (1200, 185) 216.67×36.67 |

★ 全局 +9.6 px 的来源：`root` 这条**拉伸**节点在存档里就带 `offset=(0, 9.6)`（`Ne()` 把它算成画布上移 9.6）⇒ 所有后代跟着抬 9.6（`topbar` 857 → 866.6、`hex.back` 821 → 830.6）。这是**档里原值**，不是换算器加的（见 §5.4）。

### 3.3 渲染 ✓（两张图）

* `qxqy_studio_ui_screenshot` → 编辑器舞台：能看见 `settle.btn`（左下）、`返回列表`（顶中）、`hit.*` 一排、四张蓝色卡片、中间棋盘与同心矩形、缺图占位白块（`imageId` 非 100001–100006 的图在模拟器里就是缺图框 —— **预览限制**，不是转换错误）。
* `qxqy_studio_play {start}` → `{running:true, mountError:null}`；`step dt=0.1` 后 `time=5.23 / frame=155`；`qxqy_studio_play_screenshot` → **Frame 455、pc-16-9、1600×900** 的运行时画面与舞台**同一套布局**（左下结算按钮、顶中返回列表、四卡、棋盘、右侧 `hit.*`）✓
* `pointer click (158, 70)`（＝结算按钮中心）→ `history` 记录 `{t:31.63, kind:"pointer", payload:{type:"click",x:158,y:70}}` ✓ 点击进时间线、无报错。

### 3.4 ★ 明确说明：**这次没有挂 Lua 脚本，所以没有任何脚本日志**

* 产物里 `scripts: []`、`serverLogic.rules: []`（`.gil` 里**没有** Lua 脚本映射/源码可读 ⇒ 换算器**不编造**）。
* 因此 `play get` 的 `logs: []` / `serverLogs: []` 是**预期**，**不能**算"脚本跑通了"；要点按钮的**业务反应**，需要另外把 `dist/client_script.lua` 挂到控件上（用模拟器编辑器，或 `addScript` patch），再重开试玩。
* 另一个门控提醒：插件的光标派发条件是「祖先里有 `kind==="container" && showCursor===true`」。本档里**只有 `stage` 开了 `showCursor=1`**（30 条 `containerNodeSlot` 里唯一一条），换算器**原样保留**；⇒ 在模拟器里**只有 `stage` 子树**能收光标事件，`home.select` / `settle.btn`（挂在 `root` 下）**点了不会有反应**——要试点它们，得先在最外层容器上勾「显示常驻光标」（你们文档 `docs/控件坐标表-1600x900.md` §1 门控② 也是这么写的）。

---

## 四 映射表（`.gil` 字段 → JSON 键）

字段号/语义**全部**来自插件 worker.js 里内嵌的 proto 模式文本与 GIA 读取器 `hi()/hr()/Fa()`（已抽出到 `tools/sim/out/_gia_schema.proto` 供复查），**没有一处是猜的**。

### 4.1 记录 → 节点

| `.gil` 路径 | JSON 键 | 说明 |
|---|---|---|
| 记录 `#501` | `guid` | 控件索引 |
| `#502` 里 `(field501,field502)=(2,6)` 的 `index.value` | `giaInfoIndex` | 顺序索引（存了就带） |
| `#502` 里 `(4,4)` 的 `related.value[]` | `giaRelatedGuids` | 关联 guid 列表 |
| `Data(#505)` 里 slot `2/15` → `#12.value(#501)` | `name` | 实例名 |
| `#503`（能整段解析成 ID 列表的那个） | `children`（树） | 子控件 guid 列表，**顺序照抄** |
| `#504`（顶层 varint） | 父（树） | 顶层限定，不用递归版 |
| `Data` slot `4/86` → `#14` → `#17.initiallyHidden(503)` / `#502.initiallyInactive(502)` | `visible` / `active` | |
| `Data` slot `67/90` → `footerSlot.#505` | `canControllerFocus` | `===1` |
| `MultiPlatform.#504` | `syncAllDevices` | `===1` |
| `Data` slot `63/83` → `genericSlot.#501` / `.#502[].#1.#1` | `giaRaw.genericField501` / `scriptMappingIds` | |
| `MultiPlatform.#502` | （不落 JSON） | 插件按 kind 推的「变换 preset」；本档模板记录里它是**模板号**（见 §6.4） |

### 4.2 变换（`Details.transform(#13)` → `multiPlatform(#12)`）

| `.gil` | JSON |
|---|---|
| `platforms[].platformType` 0/1/2/3 | `KEYBOARD / TOUCHSCREEN / CONTROLLER_CONSOLE / CONTROLLER_MOBILE`（`yr` 表） |
| `platforms[].transform.#501/#502/#503/#504/#505/#506/#508` | `scale / anchorMin / anchorMax / offset / size / pivot / rotation.z` |
| 缺平台槽 | 按 `KEYBOARD` 克隆（＝插件 `Fa()` 同策略）+ WARN |
| 缺分量 | 0；**NaN 分量** | 当作「缺省」（本档 510 对 NaN） |

### 4.3 各类型业务字段（按 kind，逐条照 `hr()`）

| kind | `.gil` | JSON 键 |
|---|---|---|
| 判型 | Details 槽位依次看：`textConfig(75)`→文本框（`Data.field501===71` 时是文本视窗）→ `cursorConfig(76)`→光标检测区域 → `templateRefSlot(77)`→模板引用 → `gridView(80)`→网格视窗 → `buttonPreset(81)`→预设按钮 → `keyHint(83)`→按键提示 → `imageSlot(84)/image(85)`→图片 → `effectSlot(86)`→界面动效 → `fullscreenEffectSlot(87)`→全屏动效 → 否则容器节点 | `kind` |
| 文本 | `textConfig`: `#510.text.value` / `#512` / `#502` / `#513` / `#504` / `#505` / `#506!==1` / `#507` / `#508` / `#509` | `text` / `fontSize`(默认20) / `adaptiveFontSize` / `minimumFontSize`(20) / `fontColor`(#AARRGGBB) / `bgColor` / `enableOutline` / `outlineColor` / `horizontalAlignment`{1:Middle,2:Right,否则Left} / `verticalAlignment`{0:Top,1:Middle,2:Bottom} |
| 图片 | `imageSlot.#503`→`imageId`、`imageSlot.#502`→`imageColor`；`image`: `#501/#509/#510/#511(#501,#502)/#512/#513/#514/#515/#508/#516` | `imageSource:"StaticReference"` / `imageId` / `imageColor` / `enableMask` / `enableSoftEdge` / `softEdgeMode`{Pixel,Percentage} / `softEdgeWidthX,Y` / `horizontalSoftRange` / `verticalSoftRange` / `enableFill` / `fillType`{1..5} / `fillAmount`(=`#508/100`) / `reverseMaskArea` |
| 按钮 | `buttonPreset`: `#505→interactable`、`#507→raycastTarget`、`#506→clickAudioId`(默认50888)、`#501→unavailableChildId`、`#502→hoverChildId`、`#503→pressedChildId`、`#504→selectedChildId`（四者经 guid→节点 id 映射，缺省→`null`） | 同名列 |
| 容器 | `containerNodeSlot(79)`: `#501/#502/#503/#504` | `isolateNavigation` / `disableKeyEventPassthrough` / `disableCursorEventPassthrough` / `showCursor` |
| 光标 | `cursorConfig.#501` | `raycastTarget` |
| 网格 | `gridView`: `#502,#503,#504,#505` 两分量、`#511` | `cellSizeX/Y` / `spacingX/Y` / `padding1X/Y` / `padding2X/Y` / `previewCount` |
| 按键提示 | `keyHint.#502/#501` | `keyboardKeyCode` / `controllerKeyCode` |
| 模板引用 / 动效 | `templateRefSlot` / `effectSlot` / `fullscreenEffectSlot`（字符串） | `referencedPrefabId` / `animationId` |

★ 每条的 `giaRaw`（`genericField501` / `footerField505` + 各类型 `textField* / imageField* / gridField* / …`）也照 `hr()` 的键名与默认值逐条写出，**默认值全部抄参考存档**（缺省才回退，并 WARN）。

---

## 五 坐标口径：本档混着两套（**这是本次最重要的一条发现**）

### 5.1 三套候选口径

| 代号 | 含义 | 出处 |
|---|---|---|
| **P**（父相对） | 位置 = 父中心 + 存档值；尺寸 = 存档值（画布像素） | 编辑器原生语义 + 插件 `Ne()` + 真机 GIA（`murdoku-v215-测试存档.save.json` 里 `topbar`=(0,407)、`right`=(575,-23) 与 `docs/控件坐标表-1600x900.md` 的 800,857 / 1375,427 **完全吻合**） |
| **D**（1920 设计原值） | 位置 = `(x·5/6, 900 − y·5/6)`；尺寸 `×5/6` | `tools/gil/gen_home.mjs:236-276`（`setPos(homeTitle…, 960, 195)` 直接把设计空间中心写进位置对；同一文件的注释就写着「设计坐标 1920×1080、左上原点」）＋ `docs/控件坐标表-1600x900.md` 头表「设计空间 1920×1080（左上原点、Y 向下，写代码用）／缩放 0.833333」 |
| **A**（画布绝对） | 位置 = `(800,450) + 存档值`；尺寸 = 存档值 | `tools/gil/add_button.mjs:56-61` 的换算 `posX = (rx+rw/2)·5/6 − 800`、`posY = (900 − (ry+rh/2)·5/6) − 450`；v240 文档 §1.2「存档里存的是 pos=[-642,-380] size=[217×60]（＝画布空间、相对根中心）」 |

### 5.2 逐条判定规则（`--geom=auto`，默认）

```
① 拉伸节点（anchorMin≠anchorMax，例 root）→ 原样透传（offset/size 是相对锚点矩形的增量，编辑器与插件同义）
② 父本身停在画布外（暂存区 assets、face.1.1…）→ P（跟着父停着，别搬回画布中间）
③ P 的中心落在画布内 → P
④ 否则 D 合法（0≤x≤1920, 0≤y≤1080）且矩形明显在画布内 → D
⑤ 否则 A 的中心落在画布内 → A
⑥ 否则 → P（原样）
```

本次判定结果：**D = 6 条**（下节列出）、**A = 0 条**、其余 **339 条 P**（含里面唯一的合成节点 `sc1`）。

### 5.3 D 的 6 条（逐条都核对上了真机参考值）

| 控件 | 存档原值（设计空间） | 换算到画布 | 与 v215 真机参考对照 |
|---|---|---|---|
| `home.title` | (960,195) 1000×110 | 中心 (800, 737.5) 833.33×91.67 | 参考 (800,738) 833×92 ✓ |
| `home.select` | (960,404) 460×88 | (800, 563.33) 383.33×73.33 | 参考 (800,563) 383×73 ✓ |
| `home.continue` | (960,524) 460×88 | (800, 463.33) | 参考 (800,463) ✓ |
| `home.shop` | (960,644) 460×88 | (800, 363.33) | 参考 (800,363) ✓ |
| `home.bag` | (960,764) 460×88 | (800, 263.33) | 参考 (800,263) ✓ |
| `hud.progress` | (1440,858) 260×44 | (1200, 185) 216.67×36.67 | v240 里 HUD 改过版（参考是 (1413,125) 125×50），但**右下角**这条不变量一致；按 A 读会落到 (2240,1308)（画布外）⇒ D 才自洽 |

★ 注：任务书里给的预期「`home.select` 中心 (960,404)、offset=(160,−46)、size=(460,88)」＝**A 口径**（把设计原值当画布值用）。实测**不取 A**：那样 `topbar` 会落到 x=0、`right` 会落到 (575,−23)、`settle.btn` 会跑到画布中央左、`hud.title/subtitle/timer` 会飞到屏幕中部 —— 25 条以上当场越界；而 D 一取，`home.*` 与真机参考**逐条吻合**。A 的读数随时可用 `--geom=canvas` 复现（`home.select` → offset (160,−46)、size (460,88)，与任务书一致）。

### 5.4 其它几何事实（原样保留、已在 WARN 里写明）

1. **锚点缺字段/NaN → 补 (0.5,0.5)**（148 条）：本工程口径就是「锚点选自定义 Min=Max=0.5、pivot 0.5」（`docs/控件坐标表-1600x900.md` §0 规则 2）。数值自证：`settle.btn` 存 (-642,-380) 217×60 + (0.5,0.5) ⇒ box 左 49.5 ＝ 设计 `x=60 → 画布 50` ✓（若按插件 `?? 0` 补 (0,0)，它会落到 x=−750，明显错）。
2. **NaN 当缺省**：本档 510 个两分量对是 `float NaN`（`scale / anchorMin / anchorMax / pivot`），`offset / size` 正常。插件 `Fa()` 的 `?? 0` 对 NaN 无效（NaN 不是 null/undefined）⇒ **直接导入会算出 NaN 盒**；换算器把 NaN 归一成缺省值（锚点 0.5、pivot 0.5、scale 1），并逐条 WARN。
3. **`root` 自带 `offset=(0,9.6)`**（拉伸节点，原样透传）⇒ 全部后代整体上移 9.6 px。这是档里原值（v215 真机档没有这颗偏移）；要"贴参考"可手工把 `root` 的 offset 归零，换算器**不做**这种"顺手修正"。
4. **`settle.btn` 的 `bg` / `label` 在档里没有显式尺寸**（`offset=(0,0)、size=(0,0)`）⇒ 插件预览里它们是 0 尺寸（看不见）。参考存档里同类子控件都有显式尺寸 ⇒ 这是**存档侧的缺项**，换算器原样写出并 WARN（不改数据）。

---

## 六 WARN / 回退清单（全量 240 条在 `tools/sim/out/371-v240.save.warnings.txt`）

| # | 类别 | 条数 | 原因 / 处理 |
|---|---|---|---|
| 1 | 锚点两对都缺或为 NaN，补 (0.5,0.5) | 148 | §5.4-1；数值自证过 |
| 2 | 变换 preset 与 kind 不一致 | 58（图片 34 + 容器 24） | **模板记录**（`murdoku-*` / `face*` / `letter*` / `hex` / `clue` / `tpl-container`…）的 `MultiPlatform.#502` 存的是**模板号**（9 / 105104 / 112042…）而不是插件按 kind 推的 preset；换算器**按槽位判型**（＝插件 `hi()` 同规则），并把不一致逐条列出 |
| 3 | `buttonPreset` 四状态子控件引用为空 | 30 | 档里 `#501~#504` 缺省 ⇒ 输出 `null`（参考存档里同类按钮指向具体子控件）⇒ 预览会少按钮状态外观 |
| 4 | 记录改挂到 `root` | **53**（30 + 1 + 22） | ① `#504` 缺失（原档里就是根）：**30** 条；② 父是引擎占位根 `默认布局(1073741825)`：**1** 条（`111`）；③ 父是引擎占位根 `ClientUIPrototypeHierarchyRoot(1073741844)`＝客户端模板组：**22** 条。**位置与几何一字未改**，只改挂点（参考存档里 `tpl-container` 也在 `root` 下）。注：30 与 22 两个名单里有同名控件（本档 345 条记录只有 246 个不同名字），按 **guid** 计不重复 |
| 5 | 引擎脚手架剔除 | 20 | `默认布局`+小地图/技能区/摇杆…+5 个 `*HierarchyRoot`（guid 段 1073741825…1073741844）不是用户控件；参考存档里按名查全部 false |
| 6 | 字符串/颜色/对齐等回退 | 0 | 本次**没有**发生"读不到就用参考默认"的情况；缺省值只用在「档里确实没写」的字段（如 `fontSize` 没写→20、`clickAudioId` 没写→50888），并在对应节点上 WARN |

> ⚠️ 换算器**不发明**：`.gil` 里读不到的值一律走参考存档/插件同款默认值，且**每一条都会出现在 WARN 文件里**（含控件名与原因）。

---

## 七 `--check` 交叉核对（与真机参考存档对账）

`--check="sim-save/murdoku-v215-测试存档.save.json"` 做两件事：

1. **自检盒算法**：拿参考存档自己的 `root` + `transformByPlatform` 用本换算器（照抄插件 `Ne()` 的公式）重算 1001 个盒，与参考档自带的 `boxes` 比：
   ★ **`refSelfMismatch: 0`**（left/width 误差 > 0.02 的一个都没有）⇒ 换算器的布局数学与插件**逐位一致** ✓
2. **按名对账**：参考 395 个名字里与本档同名的 102 个：**1 个完全一致、101 个有差**，其中**绝大多数差 = 恰好 9.6 px**（＝ §5.4-3 那颗 `root` 偏移，例：`hex.back` (91,821)→(91,830.6)、`topbar` 857→866.6、`right` 427→436.6），其余是真改过版的（`select.card.*` 换成了四张扑克牌、`stage` 变全屏、`bg/label` 0 尺寸）。
   ⇒ 结论：**几何换算与真机口径一致，差异可逐条解释**（口径 9.6 / 版本改版 / 存档缺项），不是"随便对不对"。

---

## 八 明确"没建立起来 / 与任务书不一致"的点

1. ★ **`select.card.1..8` 不存在**：v240 是**四关一页**（`select.card.1..4` + `hit.select.card.1..4`）。`359-选关四关一页-v227.gil` 的文件名、本档实测 4 张卡（x=338/646/954/1263 居中一排）都指向 4；任务书里的 `1..8` 应该是 v215 那代的旧形状（参考存档里确有 `select.card.8`）。
2. ★ **不是"5 个平台槽"**：`.gil` 与插件的 `transformByPlatform` 都是 **4 槽**（`KEYBOARD / TOUCHSCREEN / CONTROLLER_CONSOLE / CONTROLLER_MOBILE`，worker.js `se` + `yr` 表 + proto `repeated Platform`）。5 个的是**画布预设**（`pc-16-9 / pc-21-9 / mobile-16-9 / mobile-19.5-9 / mobile-4-3`），已按参考档原样写进 `canvas.presets` ✓。
3. **`id` 方案**：沿用插件自己的 `n${idOffset+f+1}`（`hr()` 里那张 `n` 表）⇒ 本产物用 `n<该记录在 #9/#502 扁平表里的位置+1>`（**不是** `n<bigId>`）；`guid` 单独保留在 `guid` 键里，`controlGuidChanges` / 脚本引用要认的是 guid。
4. **模板记录的 kind 存疑**：22 条客户端模板记录用的是**模板专用槽**（`Data 38/56` + `Details #47`），槽位判型只能给出 `container/image/textbox`（与插件 `hi()` 同结果），但**面板上它们本该是"客户端控件模板"**。要真正还原，得把这一类拆成 **client-control-template 资产**（插件的 GIA 导入是按 `Root.graph[].which===70` 分流的，`.gil` 里没这个标记，我只有"父是 `ClientUIPrototypeHierarchyRoot`"这条线索）。本次按参考存档的做法**放进服务端树**并 WARN。
5. **Lua / 服务端逻辑不可读**：`.gil` 里没有 Lua 源码、没有脚本映射 id、没有服务端节点图 ⇒ `scripts: []`、`serverLogic.rules: []`。**试玩里的按钮不会有业务反应**（§3.4）。
6. **模拟器存档"自动发现"列不到本文件**：`qxqy_studio_load` 不带 path 时扫工作区，本次扫到 80 个 json、`matchedArchives: 0`（连 `sim-save/*.save.json` 也没列出来）⇒ 该发现逻辑认的是另一种头部标记，不是"文件不存在"。**显式给 path 加载完全正常**（§3.1 实测就是这个路径）。

---

## 九 下一步（给接手的人）

1. 想在模拟器里**点得动**：先在编辑器把最外层容器（`root` 或 `sc1`）的「显示常驻光标」勾上（＝`showCursor=true`），或只试 `stage` 子树（它已开）。
2. 想让**按钮有反应**：把 `dist/client_script.lua`（或 v240 打包脚本）用 `addScript` 挂到 `sc1`/`root`，再 `play start` 跑 §3.2 那几条坐标做点击用例。
3. 若要让几何与真机存档**逐像素对齐**：把 `root` 的 `offset.y` 从 9.6 归零后可消掉全局 9.6 px 差（换算器层面加 `--rootOffsetZero` 即可，本次没加——因为那属于"改档"）。
4. 真机上验证时**不要用本产物**：`qxqy-simulator-save` 只进模拟器；回真机仍走 `.gil` / GIA 那条链路。
