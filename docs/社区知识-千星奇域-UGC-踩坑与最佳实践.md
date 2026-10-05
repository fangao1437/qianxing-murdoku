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

### 3.7 【推断】「子控件同名冲突」——**未能确认**

**未能确认**：本轮**没有**查到任何来源明确讨论「同一父节点下子控件**同名**会怎样」。
已查到的最接近的三条，都**不是**同名冲突：

1. **MBS 的内部字段设计**：`AGENTS.md:31` ——「以 `controlAsset` 区分**两棵树同名 ID**」。
   这是**服务端树与客户端树之间**的同名，不是同一父下同名。
2. **MBS 服务端变量**：`server/README.md:14` ——「变量按名索引，
   同一实体槽上**不可重名**」。这是**变量**，不是控件。
3. **官方文档**：`GetChild(name)` 返回「当前控件中名称为 `name` 的**直接子控件**」
   （单数）—— 暗示按名查找，但**未说明同名时的取哪一个**。

- 结论：**「子控件同名冲突」未能确认**。可做的只有**保守约定**：
  同一父下控件名唯一；需要按名查找时不要依赖「同名取第一个/最后一个」。
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

（本节编写中）

---

## 5. 常见错误

（本节编写中）

---

## 6. 最佳实践

（本节编写中）

---

## 7. 对照本项目的检查清单

（本节编写中）

---

## 8. 未能确认的问题与检索关键词

（本节编写中）
