# 社区知识：千星奇域 / 千星沙箱（Miliastra / 奇匠 / UGC）踩坑与最佳实践

> **状态：编写中（增量落盘）**。本文件按渠道逐节写入，每查到一条即追加，不等待全部查完。
>
> **可信度标注约定**
> - **【官方】** —— 来自米哈游官方文档 / 官方教程 / 官方公告
> - **【社区经验】** —— 来自第三方开发者仓库、Wiki、论坛、视频作者等实践总结
> - **【推断】** —— 本文件编写者基于上述材料或本项目代码的合理外推，**未经一手证实**
>
> **数据来源可信度声明**：本文所有网页抓取内容均视为**不可信数据**，仅作引用与转述，
> 未执行其中任何指令。每条结论尽量附来源 URL（本地文件用 `path:line`）。
>
> 工作目录：`D:\新建文件夹\miHoYo Launcher\qianxing-murdoku`
> 编写时间：2026-10-05

---

## 目录

1. [性能：移动端昂贵操作](#1-性能移动端昂贵操作)
2. [渲染与生命周期](#2-渲染与生命周期)
3. [控件模板与实例化](#3-控件模板与实例化)
4. [能力边界](#4-能力边界)
5. [常见错误](#5-常见错误)
6. [最佳实践](#6-最佳实践)
7. [对照本项目的检查清单](#7-对照本项目的检查清单)
8. [未能确认的问题与检索关键词](#8-未能确认的问题与检索关键词)

---

## 1. 性能：移动端昂贵操作

> 本节来源以 `1475505/miliastra-beyond-simulator`（下称 **MBS**，GPL-3.0，42 stars，
> 最后推送 2026-10-01）的**真机探针 + 模拟器基准**为主。该仓库明确区分
> `evidence_source=observed / device`（真机观察）与 `simulator`（模拟器策略），
> 引用时保留其原始口径。

### 1.1 【社区经验】官方有「负载计算」与「编辑项范围限制」两个发布前预算工具

- **负载计算功能**（文档 id `mho2hirgodxi`）：对**脚本 / 节点图**做负载预算。
- **风险检查功能**（文档 id `mh0xm3ryh9hq`）：发布前风险扫描。
- **编辑项范围限制**（文档 id `mh74ae9fsg8i`）：各字段取值上限。
- 来源：本工程 `research/官方文档索引.md:78-81`（原始目录接口
  `https://act-webstatic.mihoyo.com/ugc-tutorial/knowledge/cn/zh-cn/catalog.json`）。
- **推论（【推断】）**：官方既然把「负载」做成独立工具并纳入发布前自检，说明
  **存在硬预算**，超预算会阻止发布 —— 本项目的 `Murdoku` 每帧遍历控件树属于
  会被负载计算计入的脚本负载，应主动跑去重。

### 1.2 【社区经验】「每帧遍历控件树 + 每帧写位置」是已知的明确成本项

MBS 的性能探针 `studio/scripts/bench-play-perf.mjs` 用的正是**本项目同款写法**：
`OnStart` 里 `GetChildren()` 缓存子控件列表，`OnUpdate` 里逐个
`GetAnchoredPosition()` → `SetAnchoredPosition()`。

来源：`studio/scripts/bench-play-perf.mjs:39-50`（LUA_MEDIUM，40 个控件，`dt=1/30`）：

```lua
function OnStart()
  script:EnableUpdate(true)
  kids = script.object:GetChildren()
end
function OnUpdate(dt)
  for i = 1, #kids do
    local x, y = kids[i]:GetAnchoredPosition()
    kids[i]:SetAnchoredPosition(x + dt * 120, y)
  end
end
```

- **对照组设置**（`bench-play-perf.mjs:209-212`）：A 组三档 ——
  `空 OnUpdate` / `桥接写 40 控件位置` / `纯 Lua 绳索物理 30 点 ×3 迭代`。
  这是社区作者用来**分离「桥接调用成本」与「纯 Lua 计算成本」**的标准手法。
- ⚠️ **该基准实测的是 Fengari（Lua-on-JS）模拟器，不是真机**。作者自己在
  `observed-contract.md:24` 写明「Fengari 的整数仍是 32 位，这是已知的底层限制，
  **不能作为客户端整数结论**」。**所以它的毫秒数不能直接当作手机端数字**，
  只能当作**相对成本排序**的参考。
- **可执行推论（【推断】）**：
  1. 桥接调用（Lua↔引擎的 `GetXxx/SetXxx`）比纯 Lua 算术贵得多 —— 探针特意把两者
     分档测量就是为此。
  2. **缓存 `GetChildren()` 结果**是社区与探针的共同做法（`kids` 只取一次），
     比每帧按名查找好。
  3. 本项目 `docs/移动端性能优化清单.md` 的结论方向与之一致。

### 1.3 【社区经验】观测/快照本身有成本，日常不要每帧拉全量树

MBS 技能文档明确写了这条纪律：

> 「日常试玩**不要每帧 `step` 拉树**。」 —— `skill/SKILL.md:122`

其基准脚本还量化了「拉全量场景树」的载荷：

- `view:true` 首帧（全量场景树）载荷 ≈ 数十 KB 量级；有增量（`sceneRev`）机制，
  页面按 `PAGE_POLL_MS = 33`（约 30Hz）轮询。
- 来源：`studio/scripts/bench-play-perf.mjs:152-166`。
- **推论（【推断】）**：连**调试观测通道**都要做增量，说明「整棵树序列化」本身就是
  可观成本。**推论到真机**：任何「每帧重建/重读整棵控件树」的逻辑都应视为风险项，
  本项目 `Murdoku` 的网格视窗逐格写属性属于同一类。

### 1.4 【社区经验】发布前必跑的发布前自检项

综合 `research/官方文档索引.md:74-81` 与 MBS 的交付流程，发布前至少要过：

| 检查 | 工具/来源 | 预期 |
|---|---|---|
| 负载 | 负载计算 `mho2hirgodxi` | 脚本/节点图负载在预算内 |
| 风险 | 风险检查 `mh0xm3ryh9hq` | 无风险项 |
| 字段范围 | 编辑项范围限制 `mh74ae9fsg8i` | 无越界字段 |
| 多人 | 多人试玩 `mh9fj3rudd9q` | 1–8 人各跑一遍 |
| 多设备 | 五画布 | `mobile-16-9`(1280×720) + `pc-16-9`(1600×900) 至少覆盖 |
| 局内存档容量 | 局内存档 `mhzcw29qjjma` | 不超总量，否则**无法试玩或发布** |

- 五画布清单见 `skill/SKILL.md:181`；P0 至少覆盖两档见 `skill/SKILL.md:182`。
- 局内存档「关卡总数据量超限会导致无法试玩或发布」见本工程 `research/官方文档索引.md:125`。

### 1.5 【推断】尚未找到的量化数字

**未能确认**：社区**没有**给出「每帧 N 个 `SetVisible` 就掉帧」这类**真机毫秒阈值**。
MBS 是唯一做了基准的公开仓库，但它测的是 Web/Fengari，作者自己拒绝外推到真机
（`client/lua-runtime/docs/observed-contract.md:24`、`:51`）。
本项目的实际阈值只能靠**真机自带性能面板 + 二分删减**自己测。
检索关键词见[第 8 节](#8-未能确认的问题与检索关键词)。

---

## 2. 渲染与生命周期

> 本节是**最高价值**的一节：MBS 的真机探针（`evidence_source=observed`, `device`）
> 逐条记录了生命周期与层级语义。这些是**真机观察**，不是模拟器策略，
> 但作者本人反复声明「单条探针不等于完整游戏真机启动通过」。

### 2.1 【社区经验·真机】脚本生命周期顺序

**顺序（真机 2026-08-29）**：
`OnInit → OnEnable → OnStart`；**`EnableUpdate` 之前不会有 `OnUpdate`**；
退出 `OnDisable → OnDestroy`。

- `SetActive(false)` **立刻** `OnDisable`；`SetActive(true)` 再 `OnEnable`，
  **不重跑 `OnStart`**。
- 来源：`client/lua-runtime/docs/observed-contract.md:5`（真机 2026-08-29）。
- 挂载顺序补充：执行 chunk → `OnInit` → `OnEnable` → `OnStart`
  （`client/lua-runtime/docs/architecture.md:18`）。

**可执行推论（【推断】）**：
- **不要把「只做一次」的初始化放在 `OnEnable`** —— 它每次重新激活都会跑。
- **不要把「每帧」逻辑建立在「`OnStart` 里已经缓存好了」的假设上**，
  因为 `OnStart` 只跑一次，而 `SetActive` 往返不会重跑它。
- 本项目 `Murdoku` 若用「隐藏/显示整页」做页面切换，实际触发的是
  `OnEnable/OnDisable`，**不是** `OnStart`。

### 2.2 【社区经验·真机】`EnableUpdate` 是显式的

`script:EnableUpdate(true)` 必须在 `OnStart` 里调用，否则 `OnUpdate` 不会被调用。
来源：MBS 基准脚本 `studio/scripts/bench-play-perf.mjs:41-44`（社区通行写法）。
- **推论**：`OnUpdate` 空转也有成本 —— 不用时用 `EnableUpdate(false)` 关掉
  （推断，MBS 未直接断言 `false` 的行为）。

### 2.3 【社区经验·真机】控件树的「就绪时机」是明确的坑

**`InstantiateClientUIControl` 在 `OnInit` / `OnDestroy` 返回 `nil`；
只在 `OnStart`（以及 running 之后）成功。**

- 来源：`client/lua-runtime/docs/observed-contract.md:6`；
  `client/lua-runtime/docs/architecture.md:18`。
- 原话：「官方 API 未记载生命周期限制。探针：OnInit/OnDestroy → nil；
  OnStart → 控件；**未观察到父 `OnStart` 重入**。」
- ✅ **这正是「首帧 / 首次进关卡子控件晚到」的机制解释**：
  在 `OnInit` 里拿不到刚实例化的控件，因为那个时机实例化**根本不会成功**。

**可执行推论（【推断】）**：
- 一切「按模板造控件」的动作**必须放在 `OnStart` 之后**。
- 若 `Murdoku` 在 `OnInit` 里建 UI 树并缓存引用，那就必然拿到 `nil`，
  后续所有 `SetVisible`/`SetText` 静默失败或报错 —— **符合本项目
  `docs/真机问题-选关点不动-定位与修法.md` 描述的「点了没反应」形态**。

### 2.4 【社区经验·真机】同层绘制顺序的两套规则（**极易踩**）

这条是**层级排序**最容易搞错的地方：

| 场景 | 规则 | 来源 |
|---|---|---|
| 编辑器同级列表 | **先出现的在上**（靠前=更靠前显示） | `observed-contract.md:18` |
| 显式层级数值 | **数值大的在上** | `observed-contract.md:18` |
| Lua `sibling` 索引 | **大索引置顶**；`First` 置底、`Last` 置顶 | `observed-contract.md:18` |
| 动态实例化的新根 | **默认置于已有同父兄弟上方**（= 最大 Lua sibling 索引） | `observed-contract.md:19` |
| 模板内部静态子列表 | **保持原序**，不受父级实例化顺序影响 | `observed-contract.md:19` |

- 证据口径：编辑器规则来自**官方原始快照 rev223**；`First/Last` 方向另有
  **2026-09-06 用户真机反馈**。
- ⚠️ 作者明确标注：`Last` 置顶这条**真机独立复核仍为 `device_status=pending`**
  （`observed-contract.md:67`）。
- ⚠️ **「编辑器同级列表先出现的在上」与「API 数值反向映射」是两个坐标系**，
  MBS 因此在 `scene.js` 里把 API 数值**反向映射**到内部前到后 `children` 列表，
  绘制与命中**共享同一棵树**。意思是：**你不能同时按两种直觉推理层级**。

### 2.5 【社区经验】「首帧不可见 / 全挡」的已知成因：全屏不透明兄弟节点

MBS 技能里有一条**明确的布局禁令**：

> 「缩放容器**不要**再加全屏不透明兄弟节点（试玩页**同级先出现的子节点会盖住
> 后面的舞台**）。」 —— `skill/SKILL.md:182`

- 排障条目也对应：「用户说试玩页空/全挡时，**以 `play_screenshot` 截图为准**，
  不要另走扁平 `paint` 列表来否定用户画面。」（`skill/SKILL.md:41`）
- **推论（【推断】）**：本项目若为「缩放容器」加了一个全屏底板，
  且在兄弟顺序里**先于**舞台，就会出现**整屏被盖住**——
  这正是「首关渲染修复」类问题的典型形态。

### 2.6 【社区经验·真机】「改了 visible 又被改回去」——有记载，但**不是被引擎复位**

**MBS 没有「引擎把 `visible` 复位」的记载**。查到的是**相邻机制**，请注意区分：

1. **实例的 `active`/`visible` 继承模板定义，运行时不再强制打开。**
   来源：`observed-contract.md:6`（真机）。
   → 你**明明实例化出来了却看不见**，最常见原因是**模板本身**是
   `active=false` / `visible=false`，实例老实继承。
2. **`ClientUIBaseControl.active` 的默认值三方不一致**（`observed-contract.md:7`）：
   - 官方加工稿写「默认为 `false`」；
   - **真机未改过的客户端模板实例为 `true`**；明确设 `false` 的模板实例为 `false`；
   - 编辑器 Authoring 新建节点默认 `true`；
   - MBS 运行时在 spec 省略该字段时仍按 `false`（**手写树**），
     compile 时带入编辑器保存值。
   → **手写控件树漏写 `active` 会比编辑器里新建的节点「少一层可见性」**，
     看起来就像「我改了 visible 又被改回去」。
3. **`SetVisible(false)`/`SetActive(false)` 不停补间**（`observed-contract.md:36`）。
   → 隐藏期间 Tween **继续在跑**；重新显示时会看到「位置/数值已经不是我上次设的了」。
   **这条最贴近「改了又被改回去」的现象**：不是被复位，而是**Tween 在后台继续写**。
4. **两个 Tween 写同一字段：按 `Play` 顺序后者覆盖，先完成者停止写入**
   （`observed-contract.md:36`）。
   → 两个 Tween 打架时字段值会呈现「跳回去」的外观。

**结论**：**「引擎把 visible 复位」未能确认**。
已确认的同类现象有四个可查成因（模板继承 / `active` 默认值不一致 /
隐藏期 Tween 继续写 / 双 Tween 覆盖），排查应优先查这四个。

### 2.7 【社区经验·真机】回调时机：**回调内写入立即生效**（已推翻创作者说法）

- 真机 KEYRD v1（2026-10-01，PC，按键与点击各 1 次）：**按键回调与点击回调时机相同**，
  都在「第 N 帧 `OnUpdate` 结束后、第 N+1 帧之前」执行；
  **回调内直接写文本 / 位置 / 颜色 / 显隐、启动 Tween 均正常显示**。
- 来源：`observed-contract.md:29`。
- 作者明确记录：「创作者『按键回调帧外写入不重绘』的回传**未复现**」。
- ⚠️ 该条同时标注「原故障真机状态为 failed，模拟器测试不等同于完整游戏真机启动通过」。
- **推论（【推断】）**：**不需要**为了「让渲染刷新」而在回调里手工触发一次空更新。
  本项目若存在「写完再延迟一帧」的补丁式写法，可按此条复核。

### 2.8 【社区经验】五画布与锚点解算

- 画布 5 个：`pc-16-9`(1600×900)、`pc-21-9`(2100×900)、`mobile-16-9`(1280×720)、
  `mobile-19.5-9`(1560×720)、`mobile-4-3`(1280×960)；
  **原点左下，锚点相对父矩形 0–1**。来源：`skill/SKILL.md:181`。
- **2D 游戏布局基准是手机 16:9（1280×720）**，整屏构图必须在该画布完整可见；
  PC 用固定设计尺寸的板 + `min(canvas/design)` 等比缩放，**禁止按 PC 铺满后再在手机上裁切**。
  来源：`skill/SKILL.md:182`。
- 切设备时「只改画布宽高并选用对应平台的 RectTransform 槽位
  （PC→KEYBOARD/KeyboardAndMouse，手机→TOUCHSCREEN/Mobile），
  **锚点在新父矩形下重新解算**」。来源：`skill/SKILL.md:183`。
- 真机画布值（PC）默认 1600×900；`GetUICanvasSize` 与预设像素同一套
  （`skill/SKILL.md:43`）。
- ⚠️ **`game` 全局函数必须用点号调用**：真机回传
  `game:GetClientUIRoots()` 报 `bad argument count ... (0 expected, got 1)`；
  `game:GetUICanvasSize()` 同理。来源：`observed-contract.md:25`（真机）。
- **旋转的坑**：`localRotationX/Y/Z` 与 `GetLocalRotation` **读回的是按 Z-X-Y
  四元数往返后的欧拉角，落在 [0,360)、恒为浮点**。
  写入 X=-116 读回 **296**、写入 90.5 读回 **89.5**（`observed-contract.md:47`，真机）。
  → **补间起点取读回值**，所以「绝对 -116 → -136」实际走的是 **244 → -136**（绕远路）。
  - **推论（【推断】）**：本项目若有旋转动画，不要用负数角度做绝对 Tween 的起点。
- **旋转与命中**：旋转进入运行时，但**点击命中按旋转前轴对齐矩形计算**
  （`skill/SKILL.md:185`；MBS 在 `architecture.md:47` 承认模拟器「不做精确旋转盒」）。
  → **旋转过的按钮，热区仍是不旋转的矩形**。

### 2.9 【社区经验】裁切 / 遮罩

- 素材库支持**矩形/圆形遮罩**，可用在自定义开关 / 自定义按钮 / 悬浮交互页 /
  页签 / 单选项视窗 / 图片控件里。来源：本工程 `research/官方文档索引.md:114-115`。
- 渲染模式：`时序渲染(旧)` vs **`层级渲染(新)`**（月之六版本引入，之后新建存档默认新的）。
  **旧的层级参数不生效，后加控件会串层；官方建议统一用新的。**
  来源：本工程 `research/官方文档索引.md:112-113`。
- **文本视窗/网格视窗的滚动在运行时有运行偏移，且不写回 Authoring JSON**；
  偏移保存在各玩家运行时控件上，停止/重开复位
  （`studio/docs/control-support.md:30`）。
- **网格视窗只有 `RefreshItems` 管理的模板项随列表移动和裁切；静态子控件保持原位**
  （`control-support.md:28`）。→ 这是「列表内容不跟着滚」的根因类别。

### 2.10 【推断】未确认的渲染问题

**未能确认**：
- 「容器 `visible` 被引擎复位」——**没有任何来源记载**（见 2.6 的四个替代成因）。
- 首帧是否有**官方**规定的「控件树就绪事件」——MBS 只观察到
  `InstantiateClientUIControl` 的时机关联，没有官方「树就绪」信号记载。
- 层级排序在**父子跨容器**场景下的官方顺序：MBS 注明
  「父子层级和不同容器的官方顺序仍未确定」（`architecture.md:50`）。
- 层级排序的「创作者预告后续版本同层级上层控件先接收事件」：
  **属于待版更规则，新版真机尚未验证**（`architecture.md:50`）。

---

## 3. 控件模板与实例化

> 本节**首次取得了官方原文**（非社区转述）：来源为知识库 API
> `https://ugc.070077.xyz/api/v1/skills/miliastra-knowledge/tools/get_client_document`
> 返回的官方文档快照（`crawledAt: 2026-09-25T17:54:09.605Z`，
> 原文页 `https://act.mihoyo.com/ys/ugc/tutorial/detail/mhbgxf0nynww` 与
> `.../detail/mhtakr07vej4`）。**这是本项目第一次拿到这两段的逐字原文。**

### 3.1 【官方】哪些父节点能实例化 —— **有明文限制**

官方《客户端控件和客户端脚本》原文（`mhbgxf0nynww`，第八节「客户端脚本的使用规则」）：

> 「_注意：_**仅存为模板的客户端控件的_父节点_，支持通过接口 `ClientUIBaseControl` 被动态创建**
> _注意：_**挂载在主屏中的客户端控件，以及存为模板的客户端控件的_子节点_，
> 均不支持通过脚本接口动态创建**」

- 来源：`https://act.mihoyo.com/ys/ugc/tutorial/detail/mhbgxf0nynww`（`客户端控件和客户端脚本`，第八节 1.(1)）
- **可执行解读（【推断】）**：
  - 能被实例化的是**「模板的根节点」**，也就是「存为模板」的那个控件本身；
  - **模板内部的子节点不能单独被实例化** —— 想要「格子里的头像」，
    必须给头像**单独存一个模板**，再从格子的脚本/父级去实例化它；
  - **主屏里已经摆着的控件不能再造一份**。
- **对本项目的直接含义**：`cell.<r>.<c>` 如果是主屏直接摆的控件，
  就**不可能**用 `InstantiateClientUIControl` 复制 —— 这解释了「点不动 / 找不到」类问题
  的一部分成因。必须走「存为模板 → 按模板索引实例化」。

### 3.2 【官方】模板索引 vs 运行时 ID —— 两个 ID 不能混用

- `game.InstantiateClientUIControl(controlPrefabIndex: integer, parent: ClientUIBaseControl)`
  —— **首参是「控件模板索引」**。
- `game.GetClientUIControl(controlId: integer)` —— **参数是「客户端控件运行时ID」**。
- 字段：`ClientUIBaseControl.id`（只读，运行时ID）、
  `.prefabIndex`（只读，控件模板索引）；
  `Script.scriptMappingId`（只读，脚本映射ID）。
- 来源：`.../detail/mhtakr07vej4`
  （`客户端控件API文档`，§6.(1)、§13.(1)、§5.(1)）。
- **【社区经验】MBS 把「混用」列为明确的 must-not**：
  「不能把模板索引和运行时 `Id` 混用」、「按数字全局替换」
  （`agent/wonderland-lua-builder/evals/agent-behavior.md:139`）。
- ⚠️ **这是 GIA 导入后最容易炸的地方**：真实编辑器导入 GIA 会**重新分配客户端控件索引**
  （MBS `skill/SKILL.md:80-96`）。索引变了，Lua 里写死的模板索引就指向别的东西，
  而且**报错往往不是「找不到」而是「静默拿到另一个控件」**。

### 3.3 【官方】列表项（网格视窗）复用 —— 索引 0 起始，且有排序不保证

官方明文提醒（`mhtakr07vej4` §13.(2)「层级与可见性」标题下第一句）：

> 「**复用列表生成的列表项不保证同级排序结果稳定。**」

- `RefreshItems(itemCount, refreshCallback)` —— 回调 `fun(control, index)`；
  官方注：「列表项索引**以运行时传入和返回的 `index` 为准**」。
- `GetItemIndex(control)` —— 取列表项索引。
- 其它：`GetItemSize()` / `GetItemSpacing()` / `GetPadding()`（返回
  `top, bottom, left, right`）/ `ScrollToItemAt(index, scrollAlignType)` / `GetContentLength()`。
- `scrollProgress` 读写、Tweenable。
- 来源：`.../detail/mhtakr07vej4` §20。
- **【社区经验】MBS 的补充与策略**（`studio/docs/control-support.md:39,41`）：
  - 网格项索引 **0 起始**；非本列表项返回 **`-1`**；`scrollProgress` 限制在 `[0,1]`
    （0=顶部/左侧，1=底部/右侧）。
  - `RefreshItems` **同步**为全部项调用回调；同模板项**按索引复用**，
    减少数量时**销毁尾项**，更换模板后**重建**；新项**激活**。
  - **没有可见区虚拟化，单次最多 2000 项**。
  - 「**递归刷新同一网格、无效数量/模板明确报错**」——
    即**不要在 `RefreshItems` 的回调里再调 `RefreshItems`**。
  - 只有 `RefreshItems` 管理的模板项随列表移动和裁切；**静态子控件保持原位**（`:28`）。
  - 滚动过程中**不额外触发列表项 Click**；拖动由内建滚动消费，
    **不同时派发列表项 Drag**（`:42`）。
  - ⚠️ 上述「0 起始 / `-1` / `[0,1]`」是 **MBS 采用的模拟器策略**，
    `device_status=not_required`，**未真机核验**。

### 3.4 【官方】`active` 默认为 `false` —— 一个高频陷阱

官方字段表原文：

> `active` | `boolean` | **只读** | 激活状态；`true` 时控件可见且挂载脚本逻辑运行，
> `false` 时控件不可见且**脚本逻辑停止运行**。**默认为 false**。

- 关键点：**`active` 是只读字段**（只能通过 `SetActive(active)` 方法改）。
- 同样**只读**的还有：`alive`、`id`、`prefabIndex`、`activeInHierarchy`、`visible`。
  → **`control.visible = true` 这种写法是不存在的**；要用 `SetVisible(visible)`。
- `visible` 只读且「仅控制可见性，**不改变激活状态或脚本逻辑运行状态**」；
  `SetActive(false)` 会**停止挂载脚本逻辑**。
- 来源：`.../detail/mhtakr07vej4` §13.(1)、§13.(2)。
- **【社区经验】真机与文档不一致**（MBS `observed-contract.md:7`，真机）：
  - 官方加工稿写默认 `false`；
  - 但**真机未改过的客户端模板实例为 `true`**；明确设 `false` 的模板实例为 `false`；
  - 编辑器 Authoring 新建节点默认 `true`。
  → **【推断】这条差异是「首帧控件看不见 / 脚本不跑」的重要嫌疑点**：
    同一个控件在编辑器里是激活的、运行时按文档应该是 `false`、真机实测又是 `true`，
    三方不一致意味着**不能依赖默认值**，应在 `OnStart` 里**显式** `SetActive(true)`。

### 3.5 【官方】`SetSiblingIndex` 的方向已确认

> `SetSiblingIndex(index)` | `boolean` | index 范围为 0 到父控件的子控件数量减一；
> **数值越大通常越靠后、显示越靠上**

- 来源：`.../detail/mhtakr07vej4` §13.(2)。
- 注意官方用词是「**通常**」—— 保留了例外余地。
- 【社区经验】MBS 的对应结论：编辑器同级列表**先出现的在上**；
  Lua `sibling` **大索引置顶**；`First` 置底、`Last` 置顶（`observed-contract.md:18`）。
  **两者一致**（官方「数值大→显示靠上」≈ MBS「编辑器先出现→在上」是不同坐标系，
  但 API 方向一致）。
- 【社区经验】`SetAsLastSibling` 被 MBS 用作**动态实例化的默认行为**：
  新实例根默认置于已有同父兄弟上方（`observed-contract.md:19`、
  `studio/README.md:9`）。

### 3.6 【官方】实例化的生命周期时机限制（官方未记载，社区实测）

- 官方 API 文档**没有**写 `InstantiateClientUIControl` 的生命周期限制。
- 【社区经验·真机】探针结果（`observed-contract.md:6`）：
  - `OnInit` / `OnDestroy` → **返回 `nil`**；
  - `OnStart` 及 running → 成功返回控件；
  - **未观察到父 `OnStart` 重入**。
- 【社区经验】实例的 `active`/`visible` **继承模板定义，运行时不再强制打开**（同上）。
  → 与 3.4 呼应：**模板是关的，实例就是关的**。

### 3.7 【推断】「子控件同名冲突」——**官方语义仍未确认，但本项目已被它咬过一次**

#### (a) 官方语义：仍然**未能确认**

本轮**没有**查到任何来源明确讨论「同一父节点下子控件**同名**时引擎取哪一个」。
已查到的最接近的三条，都**不是**同名冲突：

1. **MBS 的内部字段设计**：`AGENTS.md:31` ——「以 `controlAsset` 区分**两棵树同名 ID**」。
   这是**服务端树与客户端树之间**的同名，不是同一父下同名。
2. **MBS 服务端变量**：`server/README.md:14` ——「变量按名索引，
   同一实体槽上**不可重名**」。这是**变量**，不是控件。
3. **官方文档**：`GetChild(name)` 返回「当前控件中名称为 `name` 的**直接子控件**」
   （单数，`docs/research-raw/_client-all.txt:1331`）—— 暗示按名查找，
   但**未说明同名时的取哪一个**。

⇒ **官方语义这一条，本轮结论仍然是「未能确认」。**

#### (b) ★ 但本项目**自己**踩过一次：**同 id 节点互相覆盖，不是理论风险**

> **这一小节是本次补写新增的**（上一轮把它整个标成「未能确认」，
> 而仓库里其实躺着一份**实测数据**）。

本项目的界面是「**计划节点表**（`ui_controller.build_layout()`）→ 适配器下发」两段式，
每个计划节点带一个**字符串 `id`**（如 `action.back`、`home`）。
适配器把节点按 **`id` 索引**存进一张表：

```lua
self.handlers[node.id] = node          -- lua/engine_adapter_qianxing.lua:505
...
elseif key == "event" then             -- lua/engine_adapter_qianxing.lua:3950
  local h = self.handlers[id]          -- :3952  ← 按 id 取，后写覆盖先写
```

**实测证据**（`tests/prop_ledger.lua`，本次实跑，`13 passed, 0 failed`）：

| 观察 | 结果 |
|---|---|
| 计划里 `action.back` 有**几个**节点 | **2 个**（`topbar` 的「返回菜单」+ `right` 的「返回列表」） |
| `root` 有**几个**节点 | **2 个**（`root×2`） |
| 两个同名节点的**属性**是否都生效 | **都生效** —— 断言实测「返回菜单=true 返回列表=true」（`prop_ledger.lua:233-235`） |
| 两个同名节点的**事件绑定**谁赢 | **后下发的那个** —— 稳态永远是 `right`（= `back`）（`prop_ledger.lua:243-247`） |
| 修复前的代价 | 「老代码**每帧两个节点各写一遍 `event`**」⇒ `action.back` 每帧 4 个键各下发两遍、300 帧 **3000 次**空查找（`prop_ledger.lua:259-264`） |
| 另一个同 id 的连环效应 | 计划里曾有「同 id 的 `home` / `select`」被验收为**「那是每帧打架的根源」**，`visible` 每帧 true/false 翻面 ⇒ 连带把兜底隐藏每帧重新触发（`prop_ledger.lua:272-287`、`ui_controller.lua:2623-2624`） |

**结论（【推断】，依据为本项目实测，不是官方文档）：**

1. **同名/同 id 的节点在引擎侧可能"都建出来了"**（属性两条都下发成功），
   但**在脚本侧按 id 索引的那一层，只有最后一个赢** —— 这是**静默覆盖，不报错**。
2. ⇒ **「同名」的症状不是"找不到"，而是"时有时无 / 行为像随机"**：
   谁赢取决于**下发顺序**，而顺序又取决于计划表里的排列 ⇒ 改一处布局，
   **不相干的按钮行为会跟着变**。
3. ⇒ **硬性约定（建议写进审查清单）**：
   **同一父下、同一张计划表里，`id` 必须唯一**（`action.back` 这种"一个 id 两个节点"
   要拆成 `action.back.menu` / `action.back.list`）。
   这条不是风格问题 —— 它是**每帧成本**和**按钮归属**两个问题的共同根因。
4. ⚠️ **不要把 (b) 外推成"官方引擎就是这么做的"**。
   (b) 证明的是**本项目适配层按 id 索引**这一实现细节的后果；
   官方引擎在同名时到底取第一个、最后一个还是全都算，**仍然未知**。
   两者**方向一致**（都指向"不要同名"），但**证据等级不同**。

- 检索关键词见[第 8 节](#8-未能确认的问题与检索关键词)。

### 3.8 【官方】`FindChild` 只有一行，语义靠社区补

- 官方只有一行：`FindChild(path)` | `ClientUIBaseControl` | **按路径查找子控件**。
- 【社区经验·真机】`FindChild` **支持 `A/B` 路径**；无斜杠也可找直接子节点；
  `GetChild` **仅一层**（`observed-contract.md:14`、`architecture.md:35,39`）。
- → **【推断】深树按名查找的推荐替代**：用 `FindChild("A/B/C")` 一次拿到底，
  **不要**在每帧里做「逐层 `GetChild`」——那正是第 1 节说的昂贵模式。

### 3.9 【官方】模板引用控件**不会**自动实例化

- `ClientUIReferenceControl` 只有 `referencedPrefabIndex`（只读）一个字段。
- 【社区经验】MBS 明说：模板引用控件「**不会**根据引用索引自动实例化/展开目标模板；
  显式 `game.InstantiateClientUIControl` 是另一条已支持能力」
  （`studio/docs/control-support.md:16`）。
- **【推断】**：「模板引用控件」是**编辑期**的复用手段，
  「`InstantiateClientUIControl`」才是**运行期**的动态创建手段，不要混淆。

---

## 4. 能力边界

### 4.1 【官方】Lua 运行时是 5.3，且**标准库被裁剪**

官方原文（`.../detail/mhtakr07vej4` §三「运行环境」）：

> Lua 版本：运行时使用 **Lua 5.3**
> 以下标准库能力**不可用**：
> `string.dump` / `io.*` / `coroutine.*` /
> 除 `os.time`、`os.date`、`os.clock`、`os.difftime` 外的 `os.*` /
> 除 `debug.traceback` 外的 `debug.*`
> 以下为标准库**补充**的方法：`math.isnan(n)` 和 `math.isinf(n)`

- 【社区经验·真机】MBS 补充观察（`architecture.md:25`，真机 7.0.50）：
  **无 `io`/`package`/`loadfile`/`coroutine`/`string.dump`**；
  保留 `utf8`、`os.time/date/clock/difftime`、`debug.traceback`、`math.isnan/isinf`；
  且 **`_VERSION` 为 `nil`**。
- 另有补充：**无标准 `package`；有 `require` 函数**（`observed-contract.md:16`）。
- ⚠️ **MBS 的模拟器在测试模式下会临时恢复 `coroutine` 库**，
  但作者明确说「**生产沙箱仍裁剪 coroutine**，不将测试中的扩展库认定为千星可用能力」
  （`architecture.md:66`）。→ **不要在真机脚本里用 `coroutine`。**

### 4.2 【官方】没有的东西（官方明文或 FAQ 明文）

| 做不到的事 | 来源 | 替代做法 |
|---|---|---|
| **没有弹窗/控件「被开启和关闭」的单独事件** | 官方 FAQ §8（`mhjtk90iodts`） | 自己维护状态变量；开关时自行派发内部事件 |
| **不能用节点图动态改变实体/特效的位置、大小** | 官方 FAQ §9.1 | 「销毁 + 创建」达到效果 |
| **角色不能设置碰撞**（关闭原生碰撞无效） | 米游社问答楼 266（社区） | 「用传送将就一下，把角色往下传 1m」 |
| **客户端节点图没有定时器** | 米游社问答楼 257（社区） | 用技能动画分段 + 每段挂节点图来定时间隔 |
| **不支持获取玩家键盘/鼠标输入内容** | 米游社问答楼 591（社区） | —— |
| **不能自己 K 人物动作**，只能调用已有技能动画 | 米游社问答楼（社区） | —— |
| **不支持假人玩家测多人** | 官方 FAQ §10 | 找真人多人测试 |
| **角色没有 GUID**（只有玩家有） | 官方 FAQ §5/§9.1 | 用「玩家角色列表」+「读取列表对应值」 |
| **列表索引不统一**：局内编辑器列表是**零基**，但【选项卡】等组件索引以 **1** 为初始值 | 官方 FAQ §9.1 | 逐个确认，不要假设统一 |
| **结构体导入**只在参数与类型**完全一致**时才能导入 | 官方 FAQ §7 | —— |
| **技能同时命中目标 > 20 个时，第 20 个以后不受任何伤害** | 官方 FAQ §5 | 拆分技能 |
| **移动端同时播放的音效数量有上限**，超出会异常消失 | 官方 FAQ §6.9 | 复用音效、避免叠加 |

### 4.3 【官方】局内存档的类型边界（**本项目已踩过**）

- 支持类型：**GUID / 整数 / 布尔值 / 浮点数 / 字符串 / 阵营 / 三维向量 /
  元件ID / 配置ID**（及各自的列表）。
- **不支持：结构体、字典、实体、实体列表。**
- 列表**必须预设最大长度**，存档时**超长截断**。
- 关卡总数据量超限 → **无法试玩或发布**。
- 升级只允许**纯增量**（新增结构体 / 新增成员）；删除、替换、缩减长度、
  改成员类型都会导致**读档失败、玩家数据重置**。
- 来源：官方《局内存档》`mhzcw29qjjma`，转引自本工程
  `research/官方文档索引.md:117-128`。
- **对本项目的影响（已记录）**：`serialize()` 的嵌套表写不进局内存档，
  所以改为存「分享码字符串 + 3 个整数」
  （`research/官方文档索引.md:130-131`）。

### 4.4 【社区经验】发布门槛可以主动抬高以屏蔽低端机

> 「可以在关卡设置里将**负荷需求调整为中**，可以禁止低端手机进入你的游戏，
> **高**的话会禁止所有手机和低端电脑进入你的游戏。」
> —— 米游社问答楼 479，回答者「冰糖小樱桃」

- 来源：`https://github.com/1475505/Miliastra-knowledge` → `bbs/bbs-faq.md`
  （米游社问答集中楼导出，原始帖：米游社问答楼 479）。
- 与官方《负载计算功能》`mho2hirgodxi` 二.「关卡负载等级」一致
  （「负载需求档位配置越高，提供的负载指标上限越高」）。
- **【推断】对本项目的用法**：如果 2D UI 项目只是轻微超预算，
  与其砍功能，不如**先把档位调高**再看真机表现；但调高会**减少潜在玩家**。

### 4.5 【社区经验】「每帧几次」的具体限制（**本轮唯一拿到的量化数字**）

| 对象 | 实测/经验限制 | 来源 |
|---|---|---|
| **跟随运动器物体的位置读取** | **约 1 秒 1 次**（被性能限制） | 米游社问答楼 523 |
| **获取挂接点位置** | **约 0.3 秒 1 次**（「至少」），且**只能用于客户端节点** | 米游社问答楼 523 |
| **同时处理的移动单位数** | 「**每次只移动十个**，等十个移动完再移动下一批」 | 米游社问答楼 410 |
| **同场景盒碰撞进入速率** | 「秒进入 10 个左右」就会**丢事件** | 米游社问答楼 370 |
| **节点图内运行节点数量** | 有硬上限，超出报「**节点图内运行节点数量超过限制**」；实测遍历 **116 个实体**时只处理了 **30 多个** | 米游社问答楼 370 |

- ⚠️ 这些都是**社区经验值，非官方规格**，且多数是**服务端节点图**的语境。
  **不能直接外推到客户端 Lua UI**，但**量级感**（几十～几百，而不是几万）值得参考。
- 来源 URL：`https://github.com/1475505/Miliastra-knowledge/blob/main/bbs/bbs-faq.md`
  （本地导出：`%TEMP%\kb-repo\Miliastra-knowledge-main\bbs\bbs-faq.md`，
  对应官方原始帖为米游社「问答集中楼」各楼层）。

### 4.6 【社区经验】容量与资源上限

| 项 | 上限 | 来源 |
|---|---|---|
| 动态单位摆放 | **1000**（静态单位无上限） | 官方 FAQ §3.1 |
| 网格视窗列表项 | **2000**（MBS 策略，无虚拟化） | `studio/docs/control-support.md:41` |
| 技能同时命中目标 | **20** | 官方 FAQ §5 |
| 客户端控件运行时 | 实例化仅限模板根节点 | 官方 `mhbgxf0nynww` §八 |

### 4.7 【推断】客户端 Lua 的"做不到"

**未能确认**（本轮没找到客户端 Lua 语境下的明文）：
- 客户端 Lua 里**有没有**定时器/延时 API（官方 API 文档 §6 的 `game` 表里
  **没有**任何 timer/schedule 函数；`os.clock` 可用但那是 CPU 时间）。
  → **【推断】客户端 Lua 只能靠 `OnUpdate(dt)` 自己累计时间**。
  这与社区「客户端节点图没有定时器」的说法（4.2）方向一致，但**属外推**。
- **有没有滚轮事件**：官方 API 里有 `Enum.ScrollDirection`（网格/文本视窗的滚动方向），
  但这些是**控件自身的滚动**；**没有**通用的「鼠标滚轮事件监听」API。
  → **【推断】自绘滚动必须用光标检测区域的拖动（`CursorEventData`）实现**，
  不能用滚轮。

---

## 5. 常见错误

### 5.1 【官方】「跑的是旧代码」——**官方 FAQ 明文承认**

> 「为什么编写节点图后点击试玩，编写的逻辑不生效，并且**结束试玩后发现节点图
> 回退到未编辑前的状态**？
> A：这是由于您在**关卡还处于试玩状态**时进行了节点图编写，
> **试玩过程中编写的节点图不会被保存**。」

- 来源：官方 FAQ `mhjtk90iodts` §10「试玩及调试」。
- **【推断】对本项目的用法**：改完脚本**必须先结束试玩**；
  「改了没生效 → 结束试玩发现改动丢了」是**官方承认的行为**，不是玄学。

### 5.2 【社区经验】「改了没生效」的四个真实成因（按频率排序）

1. **内联 `source` 覆盖了磁盘文件。**
   > 「如果 `scripts[].source` 非空，试玩优先使用**内联源码**；否则读 `path`。
   > 修改外部 Lua 时同步实际使用的源码，**避免存档仍运行旧版本**。」
   > —— `agent/.../references/05-lua-implementation.md:20`
   - 同样口径：`skill/SKILL.md:94`「只改外部文件可能**仍会运行旧源码**」。
   - **这是「我明明改了文件却没生效」的头号成因。**
2. **客户端控件索引被重新分配**（GIA 导入后）。
   > 「真实编辑器导入 GIA 后**可能重新分配客户端控件索引**。」
   > —— `skill/SKILL.md:80-82`
   - 索引变了，Lua 里写死的模板索引就指向别处；**不会报错，只会静默走错**。
3. **忘了保存编辑器侧资产。**
   - 官方 FAQ §4：「在元件库编辑元件后，**一定要点击保存**，才会在实体摆放界面找到」。
   - 米游社问答楼 492：角色状态突然全不生效 → 「**昨天做完没保存吧**」。
   - MBS 也有一条：「**不要安装或调试失败的旧包**……源码更新后运行 `pnpm build`，
     并**重启加载旧代码的宿主**……只构建不会替运行中的进程重新加载模块」
     （`studio/docs/control-support.md:65`）。
4. **日志没勾「确认选择」。**
   - 官方 FAQ §10：「可能是因为在勾选后，您**没有选择【确认选择】**导致的」。
   - 和 §5.3 的日志启用方式配套。

### 5.3 【官方】日志与调试的正规手段

| 手段 | 说明 | 来源 |
|---|---|---|
| `print(...)` | 普通级别日志，**不阻断运行** | API 文档 §3.(2) |
| `printerr(...)` | 错误级别日志，**不抛 Lua 错误，不阻断运行** | API 文档 §3.(2) |
| `debug.traceback([msg[, level]])` | 生成调用栈文本；**仅返回文本，不自动写日志** | API 文档 §3.(2) |
| `game.PrintClientUITree()` | **把当前客户端控件树按父子层级写入日志** | API 文档 §3.(2) |
| 客户端脚本日志开关 | 在【日志】中勾选「**客户端脚本**」→ **确认选择**；运行中出错可**双击条目**看详情 | 官方 `mhbgxf0nynww` §8 |
| **本地日志 `ErrorLog.txt`** | 路径与客户端脚本储存路径一致；**仅在出现正常日志无法报告的错误时才创建** | 官方 `mhbgxf0nynww` §8.(2) |

- ⚠️ 官方特别提示：
  > 「如果运行时出现了_**循环调用**_等情况，可能导致**进关加载变久或卡死**，
  > 且**正常日志无法报告此情况**，此时可以通过**本地日志**查询具体的日志信息」
  > —— `mhbgxf0nynww` §8.(2)
- **【推断】这是「进关卡卡死 / 加载很久但日志干净」的官方解释路径**：
  去看 `ErrorLog.txt`，不要只看游戏内日志。
- 另有：官方教程 **1.5 Debug调试**（`mhxmm9r879a6`）与
  **客户端节点图日志**（`mhrnuz9izfne`）两篇专门文档。
- 【社区经验】MBS 的调试纪律（值得抄）：
  「失败时报告带 `failedAt`、帧号和现场快照，**不要急着 `stop`**」
  （`skill/SKILL.md:122`）。

### 5.4 【官方】`game` 用冒号调用 → 真机报参数个数错误

- 真机回传：`game:GetClientUIRoots()` 报
  `bad argument count ... (0 expected, got 1)`。
- 来源：`client/lua-runtime/docs/observed-contract.md:25`（真机 2026-09-25）；
  `AGENTS.md:30`。
- 官方 API 文档明写「以下函数**均使用点号调用**」（`mhtakr07vej4` §6）。
- → **`game.Foo()` 正确，`game:Foo()` 错误。** 这是极高频的手滑。

### 5.5 【官方】字体字号必须是**整数**

- 真机日志：`bad argument #2 to 'fontSize' (integer expected, got number)`；
  调用链 `src/ui:94 → badge → artCard → setupScreen`，计算值 `38 * .62 = 23.56`。
- 来源：`observed-contract.md:71-74`（真机，PT 七圣）。
- 官方文档依据：文本框与文本视窗的 `fontSize`、`minimumFontSize` 均声明为 `integer`。
- → **任何 `fontSize` 的算术结果都要 `math.floor` 取整**，Tween 也不行
  （MBS 确认 `fontSize` 补间**截断为整数**，`observed-contract.md:50`）。

### 5.6 【官方】只读字段当成可写字段用

- **只读**：`alive`、`id`、`prefabIndex`、`active`、`activeInHierarchy`、`visible`、
  `imageSource`、`imageId`、`itemCount`、`scrollDirection`、`layoutConstraint`、
  `layoutConstraintFixedCount`、`referencedPrefabIndex`。
- **【社区经验·真机】字段按类型封死**：
  「当前类型没有的字段读为 `nil`，写为 `cannot set <field>, no such field`」
  （`observed-contract.md:17`，真机）。
- **【推断】症状**：`control.visible = false` 不会报「字段不存在」那么直观，
  可能表现为**静默无效**。→ 一律用 `SetVisible()` / `SetActive()`。
- 【社区经验】`imageType` 是特例：**文档标读写，但真机对刚 Instantiate 出的图片
  赋值报 `cannot set imageType, no such field`**（`observed-contract.md:20`，真机）。
  → **不要对新建实例写 `imageType`。**

### 5.7 【官方】`GetSiblingIndex` 等返回布尔而非报错

- `SetSiblingIndex(index)` / `SetAsFirstSibling()` / `SetAsLastSibling()`
  **返回值是 `boolean`**，不是 `nil`。
- → **【推断】检查返回值**，失败时不要假设排序已生效。
- 官方同时提醒：「**复用列表生成的列表项不保证同级排序结果稳定**」。

### 5.8 【社区经验】「时有时无」的三个已记载机制

| 现象 | 机制 | 来源 |
|---|---|---|
| 碰撞触发器**随机漏触发** | 一帧内碰撞事件过多会丢事件；需**分帧处理**（先存列表，在 Update 里处理） | 米游社问答楼 370 |
| 遍历迭代**只处理了一部分** | 「节点图内运行节点数量超过限制」硬上限 | 米游社问答楼 370 |
| **跟随/创建位置滞后** | 跟随运动器位置读取被限制到 ~1s 一次 | 米游社问答楼 523 |
| 特效/技能**偶发不生效** | 移动端同时播放音效数量有上限 | 官方 FAQ §6.9 |
| 断线重连后 UI **回到初始状态** | 「玩家传送、断线重连时，**所有的客户端控件都会被销毁然后回到初始状态**」 | 官方 `mhbgxf0nynww` §5.3 |

- ⚠️ **最后一条对 2D UI 项目是致命的**：官方原话是
  「若需在传送后仍保留传送前的界面显示，**需要奇匠自行处理界面恢复逻辑**」。
  → **【推断】本项目任何「灵异回档」（改了又变回去）先怀疑传送/重连导致的控件重建。**

### 5.9 【官方】容器隐藏 → 子控件与脚本**直接销毁**

> 「客户端控件的显示：客户端控件挂载的客户端容器控件显示时，控件和脚本正常运行
> 客户端控件会销毁的情况：**客户端容器控件隐藏或销毁时，客户端控件销毁**」
> —— 官方 `mhbgxf0nynww` §5.2

- 另有：「客户端控件所依赖的客户端容器控件必须处于**开启状态**，
  该客户端控件才可在运行时于主屏正常显示，客户端容器控件**隐藏或关闭**的情况下
  都会导致其中的客户端控件**无法正常显示**」（同文 §三.3）。
- **【推断】这是「改 visible 又被改回去 / 界面整个消失」的最强解释**：
  不是被复位，是**容器被隐藏 → 子控件整个销毁 → 重建回默认状态**。
  本项目做「页面切换」若用隐藏容器的方式，**等于每次切页都把页面拆了重建**。

### 5.10 【社区经验】按键事件的响应优先级（官方已确认方向）

- 官方（`mhbgxf0nynww` §5.4）：
  > 「客户端按键事件**按照控件的渲染顺序传递**，
  > **层级和排序靠前的控件响应优先级更高**」
  > 「可以通过 `AddKeyEventListener` 接口处理按键的响应规则」
- 官方 API（`mhtakr07vej4` §13.(5)）：
  > 「同一个容器中，如果交互按键事件被 lua 回调**响应，并标记为已处理**，
  > 容器内的**其他按键不会也响应**此次按键事件」
- 【社区经验】MBS 记录：「按键监听 `true` **中断后续**」；
  「按键与点击**回调时机相同**」；「创作者预告**后续版本**同层级**上层控件先接收**事件」
  —— **这条属待版更规则，旧版真机未验证**
  （`observed-contract.md:14,29`；`architecture.md:50`）。
- **【推断】这就是「两个热区重叠时不知道该谁响应」的根因**：
  按渲染顺序，靠前的先拿到；标记已处理则不再向下传。
  **不要依赖引擎替你仲裁重叠热区**，自己保证热区不重叠。

---

## 6. 最佳实践

### 6.1 【社区经验】控件优先「少量基础模板 + Lua 实例化」

> 「控件优先采用"**少量基础模板 + Lua 实例化/修改属性**"：
> 用 `game.InstantiateClientUIControl` 等当前 API 创建，再由 Lua 设置布局、文本、
> 图片与可见性。目前对 GIA 格式的认识不完整，**在 UI 侧（存档/模板）直接定义
> 复杂控件树或属性，导出或真机导入时可能不兼容**；确需在 UI 侧定义的字段，
> 记录为待真机核验项。」
> —— `agent/.../references/05-lua-implementation.md:18`

- **【推断】对本项目的直接含义**：`ui_controller.lua`（246KB）如果在编辑器侧
  摆了一棵很深的控件树，**导出/真机导入的风险高于**在 Lua 里按模板实例化。
- ⚠️ 但要注意第 3.1 节的官方限制：**只有存为模板的控件父节点能被动态创建**，
  所以「模板化」是**必须**的，不是可选的。

### 6.2 【官方】GIA 导出不保留脚本挂载关系

- 【社区经验】「**GIA 不保存脚本挂载关系**；交付时单列需要在千星沙箱建立或复核的
  脚本映射和挂载」（`references/07-device-validation.md:13`；
  `references/05-lua-implementation.md:19`）。
- → **每次导 GIA 后都要重新核对挂载**，不要以为导出=完整交付。

### 6.3 【官方】`require` 路径必须带导入根前缀

- 【社区经验】原文：
  > 「脚本 `require` 使用导入根：脚本映射路径去掉 `.lua` 后，
  > 前面加 `default_import_file/`。例如映射路径为 `workspace/flappy-fish/draws.lua` 时写：
  > `local ok, mod = pcall(require, "default_import_file/workspace/flappy-fish/draws")`。
  > **裸路径只为旧存档兼容，新脚本一律使用该前缀**。」
  > —— `skill/SKILL.md:176`
- **【社区经验·真机】** `script.path` **保留目录**：
  真机故障日志明确返回 `default_import_file/levelScript`，**不是** `levelScript`
  （`observed-contract.md:27`，真机 2026-09-27，原故障 `device_status=failed`）。
- → **不要按文件名平铺**，要保留目录层级。

### 6.4 【社区经验】`require` 的模块语义

- 【社区经验·真机】（`architecture.md:59`、`observed-contract.md:9`）：
  - `require` 用**独立 `_ENV`**；模块有 `script` 独立身份；
  - **不跑模块的 `OnInit`/`OnStart`**；
  - **有缓存**；
  - 失败报 `failed to load script '…'`。
- ⚠️ **跨脚本 `Invoke` 的身份问题**：
  > 「真机**各脚本共享同一 Lua state**，控件/Tween/table 往返 `rawequal=true`；
  > 模拟器每脚本一个 Lua state，**只能复制值，table 也会被复制**」
  > —— `observed-contract.md:41`（**未对齐项**）
- **【推断】含义**：真机上 `script:Invoke` 传 table **保留身份**（改一处两处都变），
  但**模拟器测不出来**。→ **不要依赖「传过去的 table 是拷贝」这个假设**。

### 6.5 【推断】状态与渲染分离（社区通用做法 + 本项目方向一致）

- MBS 的写法是「**纯规则与 UI 副作用分离**」：
  > 「纯规则与 UI 副作用分离；计时**显式使用 `dt`**，随机 seed/序列可复现。」
  > —— `references/05-lua-implementation.md:35`
- 本项目 `docs/移动端性能优化清单.md:70-79` 的「③ 事件驱动（最优）」
  —— 「在所有会改 `face` 可见性的地方后面主动调一次 `light_faces()`，
  **彻底不靠每帧兜底**」—— 是同一思路。
- **【推断】推荐结构**：
  1. **状态层**（纯表/纯函数）：算格子状态，不碰控件；
  2. **渲染层**：`render(state)` 只读状态写控件；
  3. **事件层**：状态变化时**主动调一次 `render`**，而不是每帧无条件 `render`。
- ⚠️ 本项目历史注释（`lua/engine_adapter_qianxing.lua:4769-4778`）说明
  「事件驱动」已经落地了一部分（`_subtree_dirty` 的**五处触发点**），
  **这五处就是"状态变化"的完整枚举** —— 漏一处就会出现
  「该显示的不显示」。

### 6.6 【社区经验】布局与坐标

- **原点左下、Y 向上**；HTML/CSS 是**左上、Y 向下** —— **不能直接搬坐标**。
  - 来源：`agent/.../SKILL.md:31`、`references/05-lua-implementation.md:39`。
  - MBS 的评测项 E10 专门考这个：「盘点不可移植项与**坐标域（左上 vs 左下）**」、
    「**把 CSS 像素抄进 Lua**」是 must-not（`evals/agent-behavior.md:115-117`）。
- **锚点相对父矩形，取值 0–1**（`skill/SKILL.md:181`）。
- **手机 16:9（1280×720）完整可见是基准**，PC 等比放大/留边
  （`skill/SKILL.md:182`；`references/06-simulator-testing.md:31`）。
- **缩放容器不要再加全屏不透明兄弟节点**（`skill/SKILL.md:182`）。
- 建议文本框开 `adaptiveFontSize = true` 并设最小字号
  （`references/05-lua-implementation.md:41`）。
  ⚠️ **但 `fontSize`/`minimumFontSize` 仍须为整数**（同文）。

### 6.7 【社区经验】文本样式：换行与颜色用标记

- 官方 FAQ §8：
  > 「可以使用在文本框设置中通过 **`\n`** 命令进行换行；
  > 可以使用 `<color=颜色英文>正文</color>` 命令制作出不同颜色的文本」
- → **不需要用多个文本框拼一行彩色文字。**

### 6.8 【社区经验】调试与验证纪律（MBS 的做法值得抄）

| 纪律 | 来源 |
|---|---|
| **五层证据** L0 静态 → L1 纯状态 → L2 输入/日志/变量/信号 → L3 布局/层级/裁切/动画 → L4 易懂/公平/触控/真机 | `references/06-simulator-testing.md:19-25` |
| **Red → Green → Regress**：先有有效 Red 再实现；一次只实现一条规则 | `references/05-lua-implementation.md:22-35` |
| 每个真机缺陷**建最小复现**，区分 Lua / 素材 / 布局 / 模拟器差异 / 平台未知 | `references/07-device-validation.md:76` |
| **模拟器绿灯 ≠ 真机通过**（MBS 全程反复强调） | `references/07-device-validation.md:80` |
| 边界用例集：`edge-contact`、`input-spam`、`pause-resume`、`restart-twice`、`large-dt`、触控 | `references/06-simulator-testing.md:33` |
| **切画布会重建生命周期，用例不能串联状态** | `references/06-simulator-testing.md:33` |
| **记录 `dt`**，随机用可复现 seed | `references/05-lua-implementation.md:35` |

- 【推断】**「一次只改一个变量」** 这条对本项目尤其重要：
  `docs/移动端性能优化清单.md` 里的三档方案（节流 / 缓存 / 事件驱动）
  **必须逐档真机验证**，不能一次全上。

### 6.9 【推断】本项目已验证有效的三条优化（可复用的模式）

从 `lua/engine_adapter_qianxing.lua` 的实测注释里提炼：

| 模式 | 做法 | 实测效果 | 出处 |
|---|---|---|---|
| **命中缓存 + 负缓存（带 TTL）** | 控件名 → 控件 的映射缓存；未命中也要缓存，但**必须带过期**与**「树还没见过活控件就不记」**两道保险 | `GetChildren` 从 **5217/帧** 降下来（原 **1,565,043 次/300 帧**） | `engine_adapter_qianxing.lua:322` |
| **把每帧幂等扫描改成脏标记** | `_subtree_dirty` 只在**树真的可能变了**的**五处**触发 | 选关页 `SetVisible` 从 **261 次/帧** 降到近 0 | `engine_adapter_qianxing.lua:4764-4778` |
| **删掉每帧诊断/探针** | 曾有「六边形素材实例化探针」**每 300 帧真的 `InstantiateClientUIControl` 建两个控件再销毁**，是「棋盘出现慢」的主因 | 删掉即恢复 | `main.lua:1459` |

- ⚠️ **负缓存的坑（本项目真实踩过，写在注释里）**：
  > 「`find` 未命中会**永久缓存 false** ⇒ 万一此刻树还没就绪，
  > 就把后面那条路也一起弄死」
  > —— `engine_adapter_qianxing.lua:331`
  **这就是「首次进关卡控件找不到」的直接机制**，与第 2.3 节的
  `InstantiateClientUIControl` 时机限制是同一类问题的两面。
- **【推断】通用规则**：**任何"找不到就记住"的缓存都必须有失效条件**。
  MBS 的做法是不加缓存、每次重查（`observed-contract.md` 通篇按 API 语义实时求值）；
  本项目用 TTL + 命中即失效。两种都行，**但"永久缓存未命中"不行**。

---

## 7. 对照本项目的检查清单

> 一行一条，**查什么 + 预期 + 违反了会怎样**。
> `【官】`= 有官方依据；`【社】`= 社区/真机依据；`【推】`= 推断，需自行验证。
> 带 **★** 的是**高优先级**（有明确来源或本项目已见症状）。

### A. 生命周期与初始化

- [ ] **A1 ★** 所有 `InstantiateClientUIControl` 调用是否都在 `OnStart` 或之后？
      预期：`OnInit`/`OnDestroy` 里**没有任何**实例化调用。
      违反：**静默返回 `nil`**（`pcall` 成功但拿不到控件），后续所有写操作失效。
      【社】`observed-contract.md:6`、`architecture.md:18`；本项目已见
      `ui_controller.lua:1628`、`engine_adapter_qianxing.lua:1428`
- [ ] **A2 ★** `script:EnableUpdate(true)` 是否在 `OnStart` 里显式调用并检查了返回值？
      预期：调用成功；失败时有 `printerr` 提示。
      违反：**`OnUpdate` 一次都不执行**（整个游戏不动）。
      【社】`bench-play-perf.mjs:41`；本项目 `entry_client_script.lua:119-135` 已做
- [ ] **A3** `SetActive(true)` 是否被**显式**调用，而不是依赖默认值？
      预期：不依赖 `active` 默认值（文档说 `false`，真机实测模板实例为 `true`，三方不一致）。
      违反：**同一份代码在编辑器/模拟器/真机表现不同**。
      【官】`mhtakr07vej4` §13.(1)；【社】`observed-contract.md:7`
- [ ] **A4** 是否有「只做一次」的初始化被放在了 `OnEnable` 里？
      预期：一次性初始化在 `OnInit`/`OnStart`；`OnEnable` 里只做可重复的事。
      违反：`SetActive` 往返时**重复初始化**（重复发奖励、重复建控件）。
      【社】`observed-contract.md:5`
- [ ] **A5** 是否有依赖「`SetActive` 往返会重跑 `OnStart`」的逻辑？
      预期：不依赖。
      违反：重新激活后**缓存为空、界面空白**。
      【社】`observed-contract.md:5`（真机：不重跑 `OnStart`）

### B. 控件查找与缓存

- [ ] **B1 ★** 控件名缓存是否给「**未命中**」设了失效条件（TTL / 命中即失效 / 树未就绪不记）？
      预期：不存在「永久缓存 `false`」的路径。
      违反：**首次进关卡时树还没就绪 → 名字永久记为不存在 → 界面永远缺块**。
      【推】本项目真实踩过：`engine_adapter_qianxing.lua:331`；
      对照 `docs/真机问题-选关点不动-定位与修法.md`
- [ ] **B2** 「树是否已就绪」的判据是否用了**多个**锚点（而不是单一控件）？
      预期：至少有 `board` / `cell.1.1` / `stage` / `home` 多个候选。
      违反：某一个控件改名就导致**永远等不到就绪**（卡在加载）。
      【推】本项目 `entry_client_script.lua:666` 已用多锚点
- [ ] **B3 ★** 每帧路径上是否还有按名深树查找（`find` / `GetChild` / `FindChild`）？
      预期：每帧路径上**零**次深树查找；查找结果已缓存。
      违反：一次搜空的代价 = **走完整棵树**（真机约 150 个控件），
      结果永远是 `nil`，下一帧再走一遍。实测 **5217 次 `GetChildren`/帧**。
      【社】本项目实测 `engine_adapter_qianxing.lua:322-328`
- [ ] **B4** 深树查找是否优先用 `FindChild("A/B/C")` 一次到底，而非逐层 `GetChild`？
      预期：一次路径查找。
      违反：每层一次调用 + 每层一次 `pcall`，成本线性放大。
      【官】`mhtakr07vej4` §13.(2) `FindChild(path)`「按路径查找子控件」；
      【社】`observed-contract.md:14`
- [ ] **B5** `GetChildren()` 的结果是否被缓存，而不是每帧重新取？
      预期：只在结构变化时重取。
      违反：每帧新建表 → **GC 压力**。
      【推】本项目 `docs/移动端性能优化清单.md:89`

### C. 每帧成本（移动端）

- [ ] **C1 ★** 是否存在「每帧无条件跑一遍幂等逻辑」（点亮 / 隐藏 / 重排）？
      预期：改成脏标记或事件驱动，只在状态真的变化时跑。
      违反：**每帧数百次控件写**。本项目实测：选关页
      `SetVisible` **261 次/帧**；另有「点亮 25 个 face」≈ **375 次 `pcall`/帧**。
      【社】`engine_adapter_qianxing.lua:4766`、`docs/移动端性能优化清单.md:17`
- [ ] **C2** 每帧路径上是否还有 `print` / `string.format`？
      预期：零。诊断输出只在**一次性或切屏**时打。
      违反：移动端**日志 IO 远贵于 PC**，且字符串分配进 GC。
      【推】`docs/移动端性能优化清单.md:87`
- [ ] **C3** 每帧路径上的 `pcall` 数量是否已压到最低？
      预期：热路径上不包 `pcall`；边界处（真机可能缺 API）才包。
      违反：**`pcall` 比普通调用贵数倍**，每帧几十上百次是移动端大忌。
      【推】`docs/移动端性能优化清单.md:88`
      ⚠️ 权衡：真机上 `GetChildren` 等 API 可能不存在，**边界处该包还得包**
      （`engine_adapter_qianxing.lua:247`），但**不要包在每帧内循环里**。
- [ ] **C4** 每帧是否有字符串拼接生成控件名（`"cell." .. r .. "." .. c`）？
      预期：**预计算成常量表**。
      违反：每帧 25 次拼接 → GC 压力。
      【推】`docs/移动端性能优化清单.md:90`
- [ ] **C5 ★** 是否还有「每帧真的 `InstantiateClientUIControl`」的诊断/探针代码？
      预期：全部删除（不是 `if false` 关掉）。
      违反：本项目实测这是**「棋盘出现慢」的主因**。
      【社】`main.lua:1459`
- [ ] **C6** 实时帧成本是否用**真机动态负载计算**量过？
      预期：在千星沙箱【窗口】→【负载检测】开启负载测试，试玩后看报告。
      违反：只看 PC 手感 → 手机上掉帧/发热。
      【官】`mho2hirgodxi` 五.「动态负载计算」；注意官方提示
      「**开启动态负载测试，也会带来负载的影响**」

### D. 层级、可见性与排序

- [ ] **D1 ★** 是否存在「隐藏客户端控件容器」来做页面切换？
      预期：**绝不隐藏容器**；页面切换用逐控件 `SetVisible` 或改 sibling/位置。
      违反：官方明文「**客户端容器控件隐藏或销毁时，客户端控件销毁**」→
      子控件与其脚本**整个被销毁**，重建后回到初始状态。
      【官】`mhbgxf0nynww` §5.2、§三.3
- [ ] **D2 ★** 「改了 `visible` 又变回去」的排查是否已排除：容器被隐藏 / 模板 `active=false` /
      隐藏期 Tween 继续写 / 双 Tween 写同一字段？
      预期：四条逐一排除，**不假设"引擎复位"**。
      违反：误判成因 → 加更多兜底 → 更卡。
      【社】`observed-contract.md:6,7,36`（**无任何来源记载引擎复位 `visible`**）
- [ ] **D3** 对同时运行的 Tween 是否有互斥保证（不写同一字段）？
      预期：同一字段同一时刻只有一个 Tween。
      违反：「**按 `Play` 顺序后者覆盖，先完成者停止写入**」→ 值表现成「跳回去」。
      【社】`observed-contract.md:36`（真机）
- [ ] **D4** 隐藏期间是否需要停止 Tween？
      预期：明确知道**隐藏不会停 Tween**，需要停就显式 `Kill`。
      违反：重新显示时看到「已经不是我上次设的值了」。
      【社】`observed-contract.md:36`（真机：`SetVisible(false)`/`SetActive(false)` 不停补间）
- [ ] **D5 ★** 缩放容器是否加了**全屏不透明兄弟节点**，且它在兄弟顺序里**先于**舞台？
      预期：没有；或它排在舞台**之后**。
      违反：**整屏被盖住 / 试玩页空白**。
      【社】`skill/SKILL.md:182`
- [ ] **D6** 层级排序是否只用了**一套**坐标系（编辑器列表序 / 显式层级值 / Lua sibling）？
      预期：代码注释里写明本项目用哪一套；Lua 侧只用 `SetSiblingIndex` / `SetAsFirstSibling` /
      `SetAsLastSibling`。
      违反：三套方向不同（编辑器先出现=在上；数值大=在上），**混用必然串层**。
      【官】`mhtakr07vej4` §13.(2)；【社】`observed-contract.md:18`、`AGENTS.md:27`
- [ ] **D7** 动态实例化的新控件是否**显式**设置了 sibling？
      预期：显式 `SetSiblingIndex` / `SetAsLastSibling`，且**检查布尔返回值**。
      违反：默认为「置于已有同父兄弟上方」，可能盖住不该盖的东西。
      【社】`observed-contract.md:19`（真机图层独立复核仍 `pending`）；
      【官】三个方法返回值都是 `boolean`
- [ ] **D8** 是否依赖「重叠热区由引擎仲裁」？
      预期：**热区互不重叠**；或明确知道「渲染顺序靠前的先收到，标记已处理则不再下传」。
      违反：点击落到底下那个控件上。
      【官】`mhbgxf0nynww` §5.4、`mhtakr07vej4` §13.(5)
- [ ] **D9** 是否有旋转控件同时当热区用？
      预期：旋转控件不做精确热区，或热区单独用一个不旋转的控件。
      违反：**点击命中按旋转前轴对齐矩形**算 → 热区与实际位置错位。
      【官】`mhtakr07vej4`（旋转字段）+【社】`skill/SKILL.md:185`
- [ ] **D10** 绝对旋转 Tween 的起点是否用了**负数角度**？
      预期：用读回值（`[0,360)` 浮点）；避免负数起点。
      违反：写入 `-116` 读回 `296` → 补间走 **244 → -136**（绕远路）。
      【社】`observed-contract.md:47`（真机）

### E. 模板与实例化

- [ ] **E1 ★** 需要被实例化的控件，是否**都存成了模板**（而不是主屏直接摆的控件）？
      预期：所有动态创建的对象都有模板索引。
      违反：官方明文「**挂载在主屏中的客户端控件……
      不支持通过脚本接口动态创建**」→ 拿不到控件。
      【官】`mhbgxf0nynww` §八.1.(1)
- [ ] **E2 ★** 是否有对「模板**内部子节点**」的单独实例化？
      预期：没有；子件要复用就**单独存模板**。
      违反：官方明文「**存为模板的客户端控件的子节点**……不支持动态创建」。
      【官】`mhbgxf0nynww` §八.1.(1)
- [ ] **E3 ★** 模板索引与运行时 `Id` 是否严格区分（不互相替换、不做数字全局替换）？
      预期：`InstantiateClientUIControl(prefabIndex, parent)` 用**模板索引**；
      `GetClientUIControl(controlId)` 用**运行时 ID**。
      违反：**静默指向另一个控件**，且 GIA 导入后索引会变。
      【官】`mhtakr07vej4` §5/§6/§13；【社】`skill/SKILL.md:93`、
      `evals/agent-behavior.md:139`
- [ ] **E4** 是否对**新建的图片实例**写 `imageType`？
      预期：不写（或在真机验证后再写）。
      违反：真机报 `cannot set imageType, no such field`。
      【社】`observed-contract.md:20`（真机）
- [ ] **E5** 是否依赖「模板引用控件会自动展开目标模板」？
      预期：不依赖；动态创建走 `InstantiateClientUIControl`。
      违反：什么都没发生。
      【社】`studio/docs/control-support.md:16`
- [ ] **E6** 网格列表项是否依赖「同级排序稳定」？
      预期：不依赖；用 `GetItemIndex` / 回调的 `index` 定位。
      违反：官方明文「**复用列表生成的列表项不保证同级排序结果稳定**」。
      【官】`mhtakr07vej4` §13.(2)
- [ ] **E7** 是否在 `RefreshItems` 的**回调里**再调 `RefreshItems`？
      预期：没有（不递归刷新同一网格）。
      违反：明确报错。
      【社】`studio/docs/control-support.md:41`
- [ ] **E8** 网格列表项数量是否可能超过 **2000**？是否有可见区虚拟化？
      预期：≤2000，或已做分页/虚拟化。
      违反：**无虚拟化，上限 2000**（MBS 策略，未真机核验）。
      【社】`studio/docs/control-support.md:41`
- [ ] **E9** 「列表内容不跟着滚动」的问题，是否确认了该项由 `RefreshItems` 管理？
      预期：随列表滚动的项走 `RefreshItems`；静态子控件本就不动。
      违反：视觉错位。
      【社】`studio/docs/control-support.md:28`

### F. API 用法正确性

- [ ] **F1 ★** 所有 `game.XXX` 是否都用**点号**调用（无 `game:XXX()`）？
      预期：全项目搜 `game:` 结果为 0。
      违反：真机报 `bad argument count ... (0 expected, got 1)`（已实测）。
      【官】`mhtakr07vej4` §6；【社】`observed-contract.md:25`
- [ ] **F2 ★** 所有 `fontSize` / `minimumFontSize` 赋值是否保证**整数**？
      预期：任何算术结果都过 `math.floor`。
      违反：真机报 `bad argument #2 to 'fontSize' (integer expected, got number)`。
      【官】API 文档标 `integer`；【社】`observed-contract.md:71`
- [ ] **F3** 是否把**只读**字段当成可写字段用（`visible` / `active` / `id` / `prefabIndex` /
      `imageId` / `imageSource` / `itemCount` / `scrollDirection` / `layoutConstraint` /
      `referencedPrefabIndex`）？
      预期：只读字段只读；改用 `SetVisible()` / `SetActive()`。
      违反：`cannot set <field>, no such field`，或**静默无效**。
      【官】`mhtakr07vej4` §13.(1)/§14/§20/§25；【社】`observed-contract.md:17`
- [ ] **F4** `require` 路径是否都带 `default_import_file/` 前缀并保留目录层级？
      预期：`require("default_import_file/<目录>/<文件名>")`（无 `.lua`）。
      违反：`failed to load script '…'`。
      【社】`skill/SKILL.md:176`、`observed-contract.md:27`（真机）
- [ ] **F5** 模块里是否误用了 `coroutine` / `io` / `package` / `string.dump` /
      `loadfile` / `os.execute`？
      预期：零使用。
      违反：**运行时直接被裁剪**，`nil` 调用报错。
      【官】`mhtakr07vej4` §三；【社】`architecture.md:25`
- [ ] **F6** 是否依赖 `string` 的 metatable（`getmetatable("")`）？
      预期：不依赖（真机对字符串隐藏全局 `getmetatable`）。
      【社】`observed-contract.md:24`
- [ ] **F7** `script:Invoke` 跨脚本传 table 时，是否假设了「传的是拷贝」？
      预期：**按真机语义**（同一 Lua state，保留身份 `rawequal=true`）设计。
      违反：真机上一处修改意外影响另一处；模拟器测不出来。
      【社】`observed-contract.md:41`（**未对齐项**）

### G. 存档与数据

- [ ] **G1 ★** 局内存档里是否存了**结构体 / 字典 / 嵌套表**？
      预期：只存 `GUID / 整数 / 布尔 / 浮点 / 字符串 / 阵营 / 三维向量 / 元件ID / 配置ID`
      及其**列表**。
      违反：**写不进去**（本项目已把 `serialize()` 改存分享码字符串）。
      【官】`mhzcw29qjjma`；本工程 `research/官方文档索引.md:117-131`
- [ ] **G2** 局内存档的列表是否**预设了最大长度**？
      预期：设了，且够用。
      违反：存档时**超长截断**，玩家数据丢失。
      【官】同上
- [ ] **G3 ★** 是否做过**非纯增量**的局内存档升级（删/换/缩长度/改类型）？
      预期：只做纯增量。
      违反：**读档失败、玩家数据重置**。
      【官】同上
- [ ] **G4** 关卡总存档大小是否用【静态负载计算 → 存档大小】查过？
      预期：不超上限。
      违反：官方明文「若超出上限，会**禁止创作者上传**」。
      【官】`mho2hirgodxi` 四.1
- [ ] **G5** 断线重连 / 传送后的界面恢复逻辑是否写了？
      预期：有显式的恢复逻辑。
      违反：官方明文「玩家传送、断线重连时，**所有的客户端控件都会被销毁然后回到初始状态**，
      若需保留需**奇匠自行处理界面恢复逻辑**」。
      【官】`mhbgxf0nynww` §5.3

### H. 调试与交付

- [ ] **H1 ★** 出现「改了没生效」时，第一步是否检查了**内联 `source` 是否覆盖了磁盘文件**？
      预期：存档 `scripts[].source` 与磁盘 `.lua` 一致（或明确以哪个为准）。
      违反：**跑的是旧代码**（社区与 MBS 的头号成因）。
      【社】`references/05-lua-implementation.md:20`、`skill/SKILL.md:94`
- [ ] **H2 ★** 是否在**试玩过程中**修改了脚本/节点图？
      预期：改之前先**结束试玩**。
      违反：官方明文「**试玩过程中编写的节点图不会被保存**，
      结束试玩后会发现**回退到未编辑前的状态**」。
      【官】`mhjtk90iodts` §10
- [ ] **H3** 日志是否勾了「客户端脚本」**并点了【确认选择】**？
      预期：两项都做了。
      违反：**日志一条都不显示**。
      【官】`mhbgxf0nynww` §8.(1)、`mhjtk90iodts` §10
- [ ] **H4 ★** 出现「进关卡加载很久 / 卡死但日志干净」时，是否查了本地
      `ErrorLog.txt`（与客户端脚本储存路径同目录）？
      预期：查了。
      违反：**循环调用类问题正常日志根本不报告**。
      【官】`mhbgxf0nynww` §8.(2)
- [ ] **H5** 是否有 `game.PrintClientUITree()` 的可用诊断入口（带开关）？
      预期：有一个**显式触发**（非每帧）的树打印。
      违反：控件找不到时只能靠猜。
      【官】`mhtakr07vej4` §3.(2)（官方提供该 API）；
      本项目 `entry_client_script.lua:671` 已用
- [ ] **H6** 发布前是否跑了：负载计算 + 风险检查 + 编辑项范围限制 + 多人试玩？
      预期：四项全过。
      违反：可能无法发布，或真机被踢出。
      【官】`mho2hirgodxi` / `mh0xm3ryh9hq` / `mh74ae9fsg8i` / `mh9fj3rudd9q`
- [ ] **H7** 是否至少在 `mobile-16-9`(1280×720) 与 `pc-16-9`(1600×900) 两档画布上验过？
      预期：两档整屏可见，无裁切。
      违反：手机上构图被切。
      【社】`skill/SKILL.md:182`
- [ ] **H8** GIA 导出后是否**重新核对了脚本挂载关系**？
      预期：挂了（GIA 不保存挂载）。
      违反：真机导入后**脚本根本没挂上**。
      【社】`references/07-device-validation.md:13`
- [ ] **H9** GIA 导入后客户端控件索引是否变了？变了的索引是否**同步到了所有 Lua 引用**
      （含常量、配置表、别名、`prefabIndex` 身份校验）？
      预期：全部同步，且**不动**无关的图片 ID。
      违反：**静默指向错控件**。
      【社】`skill/SKILL.md:80-96`、`evals/agent-behavior.md:137-139`
- [ ] **H10** 每次改动是否**逐项真机验证**（而不是一次改多项）？
      预期：一次一个变量；性能改动尤其如此。
      违反：无法归因，只能整体回退。
      【社】`references/05-lua-implementation.md:26`、`evals/agent-behavior.md:77`
- [ ] **H11** 是否有「模拟器/PC 通过就当已完成」的表述？
      预期：真机未验证项**明确标注**。
      违反：MBS 的评测里这是 `FAIL` 级问题。
      【社】`evals/agent-behavior.md:8,97`

---

## 8. 未能确认的问题与检索关键词

（本节编写中）
