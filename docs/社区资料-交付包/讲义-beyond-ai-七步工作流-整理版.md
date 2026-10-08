# 千星奇域 2D 游戏 AI 工作流 · 讲义整理版

> **原始出处**：<https://ppt.070077.xyz/beyond-ai/index.html>（课程作者的公开单页讲义）  
> **整理方式**：直接 HTTP GET 抓取线上原件（15,295,351 字节），逐页抽取**全部文字**、**27 张插图的图注（alt）**、**每页「来源」链接**与**作者「备注」**，重排为 Markdown。  
> **原件校验**：SHA256 `04DAB5924ACDA7EA20BAEABBF727DB54CC2D8D78860240DE081CF9B89A5889AE` · UTF-8（无 BOM）· `<title>` = 千星奇域2D游戏AI工作流  
> **未内嵌图片**：27 张截图合计约 11 MB（占原文件 98.2% 的体积），此处只保留图注；要看图请打开原站。  
> **相关文件**：[验证报告.md](验证报告.md) —— 对本讲义技术断言与官方文档的逐条对照  
> **抓取日期**：2026-10-09

---

## 目录

- [课程总览](#ch-intro)
- [第 1 章 · 通过Agent + 模拟器制作奇域](#ch-1)
- [第 2 章 · 集成千星沙箱相关的知识](#ch-2)
- [第 3 章 · 奇域2D美术的构建工具](#ch-3)
- [附录 · 第一次做奇域需要知道什么?](#ch-0)
- [页面索引](#页面索引)

---

<a id="ch-intro"></a>

## 课程总览

<a id="slide-cover"></a>

### 千星奇域2D游戏AI工作流

把游戏想法交给 AI，在模拟器试玩，再导入千星沙箱。

<!-- slide:cover folio:01 -->

<a id="ch-1"></a>

## 第 1 章 · 通过Agent + 模拟器制作奇域

把游戏想法做成可试玩、可导入的奇域。

<a id="slide-simulator-intro"></a>

### 1.1 “千星沙箱模拟器”可以干什么用？

让 AI 在模拟器中编辑界面、编写脚本并试玩。

01. **编辑游戏界面** — 创建控件、编写 Lua，实现画面和操作。
02. **试玩并修改** — 让 AI 操作试玩页面，根据测试结果修复问题。
03. **导入千星沙箱** — 导出控件和脚本，再配置布局、索引与脚本目录。

完成后，仍需在千星沙箱实际试玩。

[开始安装](#slide-harness)

> 🖼️ **图示 1**：模拟器 · UI 编辑工作台

> **来源**
> - [模拟器 README](https://github.com/1475505/miliastra-beyond-simulator/blob/master/README.md)

<!-- slide:simulator-intro folio:03 -->

<a id="slide-harness"></a>

### 1.2 如何安装和使用模拟器

模拟器：编辑与试玩

知识库：查询文档与 Lua 接口

01. **安装 DeepSeek Harness** — [下载桌面版](https://www.deepseek.com/harness/)
02. **安装模拟器与知识库** [模拟器插件 · 安装说明](https://github.com/1475505/miliastra-beyond-simulator/tree/master/dsh-plugin) [知识库插件 · 安装说明](https://github.com/1475505/dsh-plugin-miliastra-toolbox)
03. **启用两个插件** — 在「插件」页打开两个开关，如左图。

[下一步：准备工作区](#slide-simulator-use)
插件：安装 dsh-plugin-beyond-simulator 和 https://github.com/1475505/dsh-plugin-miliastra-toolbox。

[知识库插件](https://github.com/1475505/dsh-plugin-miliastra-toolbox)

#### MCP

让 AI 调用模拟器工具。

#### Skill

提供游戏制作步骤。

01. **连接模拟器工具** — 按 MCP 接入说明，在 AI 应用中配置模拟器。
02. **安装制作 Skill** — 接入七步工作流 Skill，再补齐知识库。
03. **使用同一个文件夹** — Web 试玩页面和 MCP 指向同一工作区，才能看到 AI 的修改。

[MCP 接入说明](https://github.com/1475505/miliastra-beyond-simulator/tree/master/mcp) [七步制作 Skill](https://github.com/1475505/miliastra-beyond-simulator/tree/master/agent/wonderland-lua-builder/skills/qxqy-game-studio)
集成下https://github.com/1475505/miliastra-beyond-simulator 和 https://github.com/1475505/Miliastra-toolbox/tree/main/skills
[模拟器仓库](https://github.com/1475505/miliastra-beyond-simulator) [知识库 Skills](https://github.com/1475505/Miliastra-toolbox/tree/main/skills)

> 🖼️ **图示 2**：两个插件均已启用

> **来源**
> - [Harness 下载](https://www.deepseek.com/harness/)
> - [模拟器插件](https://github.com/1475505/miliastra-beyond-simulator/tree/master/dsh-plugin)
> - [MCP 接入](https://github.com/1475505/miliastra-beyond-simulator/tree/master/mcp)
> - [知识库插件](https://github.com/1475505/dsh-plugin-miliastra-toolbox)
> 已安装插件的截图由课程作者提供。

<!-- slide:harness folio:04 -->

<a id="slide-simulator-faq"></a>

### 1.3 常见问题&更新指南

[查看常见问题与更新指南](https://docs.qq.com/doc/DQ0N2dHpnSktIUmpu)

<!-- slide:simulator-faq folio:05 -->

<a id="slide-simulator-use"></a>

### 1.4 模拟器怎么用

01. **准备知识库** — [查看【2】千星沙箱知识库](#slide-knowledge)
02. **选一个项目文件夹** — 工作区就是项目文件夹，如 my-game。在 AI 应用中选中它。
03. **选择游戏制作 Agent** — Harness：选择「千星 2D+Lua 游戏制作」。其他应用使用制作 Skill。
04. **描述玩法，打开试玩** — 先确认策划案；AI 给出试玩页面后，打开体验。

在当前工作区做一个 30 秒点击星星加分的单人游戏。先给策划案，确认后按七步制作，并提供试玩页面。

> 🖼️ **图示 3**：选择「千星 2D+Lua 游戏制作」预设

> **来源**
> - [Agent 预设](https://github.com/1475505/miliastra-beyond-simulator/tree/master/dsh-plugin)
> - [Web 与工作区](https://github.com/1475505/miliastra-beyond-simulator/tree/master/web)
> Agent 预设截图由课程作者提供。

<!-- slide:simulator-use folio:06 -->

<a id="slide-workflow-overview"></a>

### 1.5 七步Agent工作流

Agent：能用工具完成任务的 AI。你确认方案、试玩反馈，AI 按七步制作。

> 🖼️ **图示 4**：千星 2D+Lua 游戏制作 · Agent 预设

> **来源**
> - [七步 Agent 工作流](https://github.com/1475505/miliastra-beyond-simulator/blob/master/agent/wonderland-lua-builder/README.md)
> Agent 预设截图由课程作者提供。七步名称以仓库工作流说明为准。

<!-- slide:workflow-overview folio:07 -->

<a id="slide-step-01"></a>

### 1.6 策划案

> **七步Agent工作流** · STEP 01

先确认一页策划案。下面用“点击星星”贯穿七步。

01. **目标** — 30 秒内点击星星，每点一次加 1 分。
02. **操作** — 电脑点击；手机触摸。点击后，星星换一个位置。
03. **结束** — 倒计时归零后展示分数，可以重新开始。
04. **先做什么** — 先完成单人玩法；美术用简单星星。

[官方教程：点击收集玩法](https://act.mihoyo.com/ys/ugc/tutorial/course/detail/mh47p30a87qo?tk=course_all)

> **来源**
> - [步骤 01 · 策划案](https://github.com/1475505/miliastra-beyond-simulator/blob/master/agent/wonderland-lua-builder/skills/qxqy-game-studio/references/01-game-design.md)
> 千星沙箱模拟器 · qxqy-game-studio 工作流原文。
> 点击星星是本课程编写的教学示例，用于展示每一步的交付内容。官方点击收集玩法教程作为延伸阅读。

<!-- slide:step-01 folio:08 -->

<a id="slide-step-02"></a>

### 1.7 TDD 制定测试用例

> **七步Agent工作流** · STEP 02

先让 AI 列出检查表：怎么操作，应该看到什么。

| 操作 | 预期结果 |
|---|---|
| 点击开始 | 得分 0；倒计时从 30 秒开始。 |
| 点击一次星星 | 得分 +1；星星换位置。 |
| 倒计时归零 | 停止加分，展示本次分数。 |
| 重新开始 | 得分清零，重新计时。 |
| 在手机上试玩 | 星星可点中，画面与按钮完整显示。 |

确认这张检查表，后面按它逐项验收。

> **来源**
> - [步骤 02 · TDD 制定测试用例](https://github.com/1475505/miliastra-beyond-simulator/blob/master/agent/wonderland-lua-builder/skills/qxqy-game-studio/references/02-test-cases.md)
> 千星沙箱模拟器 · qxqy-game-studio 工作流原文。
> 点击星星是本课程编写的教学示例，用于展示每一步的交付内容。

> 📝 **作者备注**：复杂逻辑可以录制行为，后期进行自动化试玩验收。

<!-- slide:step-02 folio:09 -->

<a id="slide-step-03"></a>

### 1.8 HTML 效果展示

> **七步Agent工作流** · STEP 03

先得到一个能在浏览器试玩的游戏原型。
点击星星 HTML 教学示例 得分 0 剩余 30 秒 点击开始，再点击星星
01. **先试一局** — 点击左侧「开始试玩」。试试加分、结束和重开。
02. **告诉 AI 哪里不顺手** — 例如：星星太小、移动太快、分数不够醒目。
03. **满意后再做 Lua** — 确认操作和画面，再进入千星脚本实现。

此处是教学原型；千星沙箱里的效果要在导入后验证。

> **来源**
> - [步骤 03 · HTML 效果展示](https://github.com/1475505/miliastra-beyond-simulator/blob/master/agent/wonderland-lua-builder/skills/qxqy-game-studio/references/03-html-prototype.md)
> 千星沙箱模拟器 · qxqy-game-studio 工作流原文。
> 点击星星是本课程编写的教学示例，用于展示每一步的交付内容。

<!-- slide:step-03 folio:10 -->

<a id="slide-step-04"></a>

### 1.9 准备千星美术参考图和素材

> **七步Agent工作流** · STEP 04

画面草图 点击星星 得分 0 剩余 30 秒 ★ 开始游戏
01. **素材：星星** — 轮廓清楚，和背景容易区分。
02. **界面：分数、时间与按钮** — 提供参考界面，说明各部分的位置。
03. **确定制作方式** — 用拼图或图元拟合工具制作素材。

[查看美术工具与实例](#slide-art)

> **来源**
> - [步骤 04 · 准备千星美术参考图和素材](https://github.com/1475505/miliastra-beyond-simulator/blob/master/agent/wonderland-lua-builder/skills/qxqy-game-studio/references/04-art-assets.md)
> 千星沙箱模拟器 · qxqy-game-studio 工作流原文。
> 点击星星是本课程编写的教学示例，用于展示每一步的交付内容。

<!-- slide:step-04 folio:11 -->

<a id="slide-step-05"></a>

### 1.10 Lua 编码实现

> **七步Agent工作流** · STEP 05

01. **Lua：响应操作的脚本** — 点击星星、更新分数、倒计时和重开，由 AI 实现。
02. **打开模拟器试玩** — 检查星星能否点击、得分能否更新、倒计时能否结束。
03. **保存制作成果** — 保留 .lua 脚本和完整 .save.json，后面修改与导入都要用。

> 🖼️ **图示 5**：Lua 脚本界面 · 示例项目：纸映成戏

> **来源**
> - [步骤 05 · Lua 编码实现](https://github.com/1475505/miliastra-beyond-simulator/blob/master/agent/wonderland-lua-builder/skills/qxqy-game-studio/references/05-lua-implementation.md)
> Lua 脚本截图由课程作者提供。
> 点击星星是本课程编写的教学示例，用于展示每一步的交付内容。

<!-- slide:step-05 folio:12 -->

<a id="slide-step-06"></a>

### 1.11 测试

> **七步Agent工作流** · STEP 06

让 AI 交付测试结果：哪些通过，哪些需要修复。

01. **按检查表操作** — 开始 → 点击 → 等到结束 → 重开，再检查手机画面。
02. **记录问题** — 例如：点击星星后没有加分。附操作、截图或日志。
03. **修改后再测** — 重做失败的检查，并确认之前通过的功能仍然可用。

请按测试用例操作模拟器，逐项报告实际结果。发现失败项后修复，再重新测试。

> **来源**
> - [步骤 06 · 测试](https://github.com/1475505/miliastra-beyond-simulator/blob/master/agent/wonderland-lua-builder/skills/qxqy-game-studio/references/06-simulator-testing.md)
> 千星沙箱模拟器 · qxqy-game-studio 工作流原文。
> 点击星星是本课程编写的教学示例，用于展示每一步的交付内容。

<!-- slide:step-06 folio:13 -->

<a id="slide-step-07"></a>

### 1.12 真机试玩验证与 bug 修复

> **七步Agent工作流** · STEP 07

真机试玩：把作品导入千星沙箱，在实际游戏中玩一遍。

01. **导入并试玩** — 按后面的导入步骤，检查开始、加分、结束和重开。
02. **把问题反馈给 AI** — 例如：“模拟器能加分，千星沙箱里点星星后分数不变。”附操作、截图与日志。
03. **修改，再试玩** — 让 AI 修复；更新脚本后，在千星沙箱保存并重新试玩。

> **来源**
> - [步骤 07 · 真机试玩验证与 bug 修复](https://github.com/1475505/miliastra-beyond-simulator/blob/master/agent/wonderland-lua-builder/skills/qxqy-game-studio/references/07-device-validation.md)
> 千星沙箱模拟器 · qxqy-game-studio 工作流原文。
> 点击星星是本课程编写的教学示例，用于展示每一步的交付内容。

<!-- slide:step-07 folio:14 -->

<a id="slide-gia-export"></a>

### 1.13 导入到千星沙箱

01. **模拟器：导出作品** — 加载 .save.json，导出「GIA 整合包（控件+脚本）」。
02. **千星沙箱：导入资产** — 新建存档，打开资产目录并放入 GIA。加载外部资产后，转存所选资产。
03. **千星沙箱：显示界面** — 将控件组加入界面布局。进入客户端控件容器的画布设置，给容器节点挂载入口脚本。
✓
布局中能看到导入的客户端控件容器。

[继续：索引核对](#slide-gia-handoff)

> 🖼️ **图示 6**：① 模拟器：导出 GIA 整合包

> 🖼️ **图示 7**：③ 千星沙箱：加入客户端控件容器

> **来源**
> - [资产导入导出](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhxbd59urbfu)
> - [模拟器导入与导出](https://github.com/1475505/miliastra-beyond-simulator/tree/master/web)
> - [客户端控件和客户端脚本](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhbgxf0nynww)
> GIA 导出菜单截图由课程作者提供。

<!-- slide:gia-export folio:15 -->

<a id="slide-gia-handoff"></a>

### 1.14 索引核对

01

#### 千星沙箱：查看控件或模板的索引

02

#### 模拟器：找到同一个控件，填写实际索引

索引变化时，让 AI 更新 Lua 中的对应引用，再保存存档。

[下一步：路径绑定](#slide-gia-path-binding)

> 🖼️ **图示 8**：千星沙箱：查看索引（位置示例）

> 🖼️ **图示 9**：模拟器：填写索引（位置示例）

> **来源**
> - [客户端控件与模板索引](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhbgxf0nynww)
> - [控件与索引](https://github.com/1475505/miliastra-beyond-simulator/blob/master/editor-ui/README.md)
> 索引位置配图来自本地官方指南快照；两张截图展示查看与填写入口，不是同一个控件。实际操作请核对同一个资产。模拟器索引截图由课程作者提供。

<!-- slide:gia-handoff folio:16 -->

<a id="slide-gia-path-binding"></a>

### 1.15 路径绑定

01

#### 千星沙箱：获取脚本目录

打开客户端脚本资源管理器，双击已导入的脚本，获取脚本所在目录。

02

#### 模拟器：绑定当前关卡目录

Lua 脚本 → 实机脚本同步。按脚本路径核对并绑定目录，也可用「发现本机目录」选择当前关卡。

03

#### 检查差异，确认复制

保存目录配置 → 保存存档并检查差异 → 确认复制。回到千星沙箱保存并重新试玩。

> 🖼️ **图示 10**：千星沙箱：客户端脚本资源管理器中的脚本

> 🖼️ **图示 11**：模拟器：发现本机目录，选择自己的关卡

> **来源**
> - [客户端控件和客户端脚本](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhbgxf0nynww)
> - [实机脚本同步](https://github.com/1475505/miliastra-beyond-simulator/blob/master/studio/docs/script-sync.md)
> 客户端脚本资源管理器截图及“双击脚本获取目录”操作由课程作者提供。请按实际脚本路径核对导入根目录与对应子目录，保留脚本映射的目录层级。模拟器目录截图已遮挡本机用户名；示例路径不用于其他项目。

<!-- slide:gia-path-binding folio:17 -->

<a id="ch-2"></a>

## 第 2 章 · 集成千星沙箱相关的知识

让 AI 查到千星沙箱文档与 Lua 接口。

<a id="slide-knowledge"></a>

### 2.1 千星沙箱知识库

模拟器负责编辑与试玩；知识库提供官方文档、经验与 Lua 接口。

#### DeepSeek Harness

安装知识库插件，会包含通用文档和客户端 Lua 知识。

[知识库插件](https://github.com/1475505/dsh-plugin-miliastra-toolbox)

#### 其他 AI 应用

安装知识库 Skill：通用知识与客户端 Lua 分别接入。
[通用知识 Skill](https://skillhub.cn/skills/user_3a6be892/miliastra-toolbox) [客户端 Lua Skill](https://github.com/1475505/Miliastra-toolbox/tree/main/skills/miliastra-knowledge-lua) [返回「模拟器怎么用」](#slide-simulator-use)

> **来源**
> - [知识库插件](https://github.com/1475505/dsh-plugin-miliastra-toolbox)
> - [知识库 Skill](https://skillhub.cn/skills/user_3a6be892/miliastra-toolbox)

<!-- slide:knowledge folio:19 -->

<a id="slide-toolbox"></a>

### 2.2 知识库问答服务

#### 有节点图问题，可以直接问网页知识库。

例如：

玩家走进区域后开门，需要哪些节点？每个节点应该连到哪里？

[https://ugc.070077.xyz](https://ugc.070077.xyz)
网页问答不含 Lua；Lua 文档通过前页的知识库接入。

> 🖼️ **图示 12**：嘟嘟可工具箱 · 知识库问答

> **来源**
> - [知识库插件](https://github.com/1475505/dsh-plugin-miliastra-toolbox)
> - [https://ugc.070077.xyz](https://ugc.070077.xyz)
> 网页界面截图；Lua 知识范围按课程作者提供的信息。

<!-- slide:toolbox folio:20 -->

<a id="ch-3"></a>

## 第 3 章 · 奇域2D美术的构建工具

从画面效果出发，选择合适的美术工具。

<a id="slide-art"></a>

### 3.1 如何优化2D的美术效果

平面图形配合层次和动画，也能呈现立体感。以下是作者的实机效果。

> 🖼️ **图示 13**：实机画面 · 场景

> 🖼️ **图示 14**：实机画面 · 角色

<!-- slide:art folio:22 -->

<a id="slide-puzzle"></a>

### 3.2 拼图工具

想组合、调整图形时使用。

01. **拼出画面** — 从图形库拖入素材，调整位置、颜色与层次。
02. **导出到游戏** — 导出 GIA 或 Lua，交给 AI 接入游戏。

[https://qx.070077.xyz](https://qx.070077.xyz)

#### 用 AI 操作

支持 WebMCP 的 AI / 浏览器可操作此工具。

[美术构建 Skill](https://skillhub.cn/skills/user_3a6be892/miliastra-image-css-builder)

> 🖼️ **图示 15**：拼图工具 · 编辑示例

> **来源**
> - [https://qx.070077.xyz](https://qx.070077.xyz)
> - [美术构建 Skill](https://skillhub.cn/skills/user_3a6be892/miliastra-image-css-builder)
> 截图由课程作者提供；页面提供 WebMCP 工具。

<!-- slide:puzzle folio:23 -->

<a id="slide-primitive"></a>

### 3.3 图元拟合&GIA转换工具

#### 有参考图：拟合成图形

上传图片，选择图形与数量，再开始拟合。

得到由圆形、矩形、三角形等组成的画面。

#### 已有 GIA：转换格式

上传 GIA，选择经典 / 超限模式转换。

素材组也可转为 Lua，用于超限模式。

[https://qx-img.070077.xyz](https://qx-img.070077.xyz)

> 🖼️ **图示 16**：图元拟合工具 · 图片拟合

> 🖼️ **图示 17**：图元拟合工具 · GIA 转换

> **来源**
> - [https://qx-img.070077.xyz](https://qx-img.070077.xyz)
> - [工具源码](https://github.com/1475505/Miliastra-toolbox-primitive-shape)
> 界面截图核对于 2026-10-03。素材组 GIA 转 Lua 输出用于超限模式。

<!-- slide:primitive folio:24 -->

<a id="ch-0"></a>

## 附录 · 第一次做奇域需要知道什么?

关卡设置、结算、日志与资产，按需查阅。

<a id="slide-client-server"></a>

### 附.1 服务端、客户端

客户端负责本地逻辑与 UI 画面；服务端负责共享状态。

#### 大家共用一份服务端 同步多名玩家的行为，获取其他实体的状态。

客户端发送操作 · 服务端同步结果 运行在你的电脑或手机上 #### 你的客户端 响应操作、执行本地逻辑、显示 UI 画面。

运行在另一位玩家的电脑或手机上 #### 另一位玩家的客户端 响应操作、执行本地逻辑、显示 UI 画面。

1 位玩家 · 1 份客户端

> **来源**
> - [客户端控件和客户端脚本](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhbgxf0nynww)
> - [客户端控件 API 文档](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhtakr07vej4)
> - [https://ugc.070077.xyz](https://ugc.070077.xyz)
> 依据《千星沙箱客户端脚本使用指南》的本地玩法、界面表现及两端通信说明；实体状态依据知识库《查询节点》中的服务端「查询实体是否在场」「获取实体位置与旋转」。树状图为职责与连接关系示意，通信方式见本章末尾的信号页；未表示相关查询只能在服务端进行。

> 📝 **作者备注**：一份服务端连接每位玩家的客户端。客户端负责本地逻辑与 UI 画面；服务端处理共享状态、同步多人行为并查询其他实体状态。单人与多人可切换查看。

<!-- slide:client-server folio:26 -->

<a id="slide-level-settings"></a>

### 附.2 关卡设置

#### 单人关卡

关卡设置 → 人数设置。

选择「固定人数」，将人数改为 1。

#### 背景音乐

系统菜单 → 背景音乐管理。

选择音乐，调整音量与循环。

> 🖼️ **图示 18**：官方文档 · 人数设置示例

> 🖼️ **图示 19**：官方文档 · 背景音乐管理

> **来源**
> - [关卡设置](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhn9vpia00qc)
> - [背景音乐](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhq9b601kh9k)

<!-- slide:level-settings folio:27 -->

<a id="slide-settlement"></a>

### 附.3 结算

结算：结束关卡，让玩家看到本次结果。

01. **按钮退出** — 按钮触发「结算关卡」，结束本次游玩。
02. **ESC 退出** — 「逃跑合法性」决定这次离开是否记为逃跑。
03. **胜利还是失败** — 「结算成功状态」决定合法退出时的结果。

> 🖼️ **图示 20**：设置玩家结算成功状态

> 🖼️ **图示 21**：设置玩家逃跑合法性

> 🖼️ **图示 22**：结算关卡

> **来源**
> - [关卡结算](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhx1du08nhwo)
> - [交互按钮界面控件](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhwkfsitckrw)
> 节点图片来自官方节点库。按钮 / ESC 为课程指定的退出方式。

> 📝 **作者备注**：录制前核对当前版本 ESC 退出行为。

<!-- slide:settlement folio:28 -->

<a id="slide-logs"></a>

### 附.4 日志

1. **打开日志** — 千星沙箱：窗口 → 日志
2. **找到报错** — 勾选「客户端脚本」，再做一次出错的操作。
3. **发给 AI** — 双击报错，把详情和操作步骤一起发给 AI。

操作：点击开始。预期：出现游戏画面。实际：画面空白。下面是报错详情，请根据日志排查。

> 🖼️ **图示 23**：客户端脚本使用指南 · 日志面板

> **来源**
> - [客户端控件和客户端脚本](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhbgxf0nynww)
> - [节点图日志](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhu951iz7wz8)

<!-- slide:logs folio:29 -->

<a id="slide-assets"></a>

### 附.5 资产导入及使用

01. **.gia：导入素材与脚本** — 资产导入导出工具 → 打开目录。放入 GIA 后，加载外部资产。
02. **.gil：完整关卡存档** — 千星沙箱的存档页面 → 导入存档。
03. **.save.json：模拟器存档** — 保留 AI 制作的界面与脚本，之后在模拟器里继续修改。

[返回模拟器章节](#slide-chapter-1) [继续看进阶知识](#slide-entities)

> 🖼️ **图示 24**：官方文档 · 资产导入导出工具

> **来源**
> - [资产导入导出](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhxbd59urbfu)
> - [1.4存档导入与导出](https://act.mihoyo.com/ys/ugc/tutorial/course/detail/mhjuwpiubrh0)
> - [模拟器存档与导出](https://github.com/1475505/miliastra-beyond-simulator/blob/master/README.md)

<!-- slide:assets folio:30 -->

<a id="slide-entities"></a>

### 附.6 关卡、玩家实体

> **进阶知识**

沙箱用「实体」表示游戏里的对象。

例：两位玩家进入同一关卡 这一局游戏 

#### 关卡实体 · 1 个 关卡自带，不能手动新增或删除。

#### 玩家 A 的玩家实体 代表进入关卡的玩家 A。

#### 玩家 B 的玩家实体 代表进入关卡的玩家 B。

玩家实体本身没有可见模型，与角色实体不同。

> **来源**
> - [关卡设置](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhn9vpia00qc)
> - [玩家](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhctmgi51lpo)
> 关系图为概念示意。关卡实体随关卡创建；玩家实体是没有物理模型的逻辑实体。

> 📝 **作者备注**：先认识对象，不在本页引入自定义变量、得分或信号。示意人数为两人；玩家实体与角色实体不同。

<!-- slide:entities folio:31 -->

<a id="slide-variables-nodes"></a>

### 附.7 自定义变量与节点图

> **进阶知识**

例：给每位玩家记录本局得分。把这份数据命名为「得分」。

#### 1. 先定义要保存的数据和数据类型

玩家编辑 → 组件 → 自定义变量 → 详细编辑

新增「得分」：类型为整数，初始值为 0。
玩家 A 0 玩家 B 0

#### 2. 再用节点图修改它

「设置自定义变量」节点： 目标实体选玩家 A，变量名填「得分」，变量值设为 1。

玩家 A、玩家 B 的得分各存一份。

> 🖼️ **图示 25**：玩家编辑 → 组件 → 自定义变量

> 🖼️ **图示 26**：设置自定义变量

> **来源**
> - [自定义变量](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhso1b9wjica)
> - [玩家](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhctmgi51lpo)
> - [基础概念](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhk23ora1wom)
> 得分名称与数值为教学示例，页面按钮是概念演示。自定义变量存放在实体的组件中；本例放在玩家实体上。普通自定义变量跟随实体生命周期，跨局保存另需局内存档。本页只说明定义与赋值，不是完整的事件连线教程。截图为已引用的官方文档原图。

> 📝 **作者备注**：每页只完成一个例子：玩家组件中新建整数变量得分，再用服务端设置自定义变量节点赋值。普通变量不是跨局存档。

<!-- slide:variables-nodes folio:32 -->

<a id="slide-signal-nodes"></a>

### 附.8 用信号连接两端

> **进阶知识**

信号是广播传递的消息。例：把一位玩家的操作通知给所有在场玩家。

1. 监听信号： 接收 topo5_pvp_send，开始执行。
2. 列表迭代循环： 获取在场玩家，依次选为目标玩家。
3. 发送客户端脚本信号： 向该玩家发送 topo5_pvp_event。

客户端脚本监听 topo5_pvp_event，再更新画面。两个信号名均需先在信号管理器中定义。

> 🖼️ **图示 27**：服务端节点图：监听信号、遍历在场玩家、发送客户端脚本信号

> **来源**
> - [信号](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhlaj0r9bldi)
> - [客户端控件和客户端脚本](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhbgxf0nynww)
> - [客户端控件API文档](https://act.mihoyo.com/ys/ugc/tutorial/detail/mhtakr07vej4)
> 节点图截图由课程作者提供；图片仅通过显示区域裁切，放大可见完整原图。截图的 topo5_pvp_send 与 topo5_pvp_event 是两种不同的自定义消息，分别用于客户端到服务端、服务端到客户端；参数原样转发。监听信号是广播事件，每个监听该信号的实体都可能执行；此图遍历在场玩家，将客户端消息逐个发送。截图不是本轮运行验证。

> 📝 **作者备注**：按白色执行连线看三个节点；蓝线承载操作参数。发送端与监听端的信号名应相同。服务端向客户端使用发送客户端脚本信号，Lua 用 RegisterServerSignalHandler 注册处理回调。

<!-- slide:signal-nodes folio:33 -->

---

## 页面索引

| 原页 | 页 id | 章节 | 标题 | 图数 | 备注 |
|---:|---|---|---|---:|---|
| 01 | [`cover`](#slide-cover) | 总览 | 千星奇域2D游戏AI工作流 | 0 |  |
| 02 | [`chapter-1`](#slide-chapter-1) | 第 1 章 | 通过Agent + 模拟器制作奇域 | 0 |  |
| 03 | [`simulator-intro`](#slide-simulator-intro) | 第 1 章 | “千星沙箱模拟器”可以干什么用？ | 1 |  |
| 04 | [`harness`](#slide-harness) | 第 1 章 | 如何安装和使用模拟器 | 1 |  |
| 05 | [`simulator-faq`](#slide-simulator-faq) | 第 1 章 | 常见问题&更新指南 | 0 |  |
| 06 | [`simulator-use`](#slide-simulator-use) | 第 1 章 | 模拟器怎么用 | 1 |  |
| 07 | [`workflow-overview`](#slide-workflow-overview) | 第 1 章 | 七步Agent工作流 | 1 |  |
| 08 | [`step-01`](#slide-step-01) | 第 1 章 | 策划案 | 0 |  |
| 09 | [`step-02`](#slide-step-02) | 第 1 章 | TDD 制定测试用例 | 0 | ✓ |
| 10 | [`step-03`](#slide-step-03) | 第 1 章 | HTML 效果展示 | 0 |  |
| 11 | [`step-04`](#slide-step-04) | 第 1 章 | 准备千星美术参考图和素材 | 0 |  |
| 12 | [`step-05`](#slide-step-05) | 第 1 章 | Lua 编码实现 | 1 |  |
| 13 | [`step-06`](#slide-step-06) | 第 1 章 | 测试 | 0 |  |
| 14 | [`step-07`](#slide-step-07) | 第 1 章 | 真机试玩验证与 bug 修复 | 0 |  |
| 15 | [`gia-export`](#slide-gia-export) | 第 1 章 | 导入到千星沙箱 | 2 |  |
| 16 | [`gia-handoff`](#slide-gia-handoff) | 第 1 章 | 索引核对 | 2 |  |
| 17 | [`gia-path-binding`](#slide-gia-path-binding) | 第 1 章 | 路径绑定 | 2 |  |
| 18 | [`chapter-2`](#slide-chapter-2) | 第 2 章 | 集成千星沙箱相关的知识 | 0 |  |
| 19 | [`knowledge`](#slide-knowledge) | 第 2 章 | 千星沙箱知识库 | 0 |  |
| 20 | [`toolbox`](#slide-toolbox) | 第 2 章 | 知识库问答服务 | 1 |  |
| 21 | [`chapter-3`](#slide-chapter-3) | 第 3 章 | 奇域2D美术的构建工具 | 0 |  |
| 22 | [`art`](#slide-art) | 第 3 章 | 如何优化2D的美术效果 | 2 |  |
| 23 | [`puzzle`](#slide-puzzle) | 第 3 章 | 拼图工具 | 1 |  |
| 24 | [`primitive`](#slide-primitive) | 第 3 章 | 图元拟合&GIA转换工具 | 2 |  |
| 25 | [`chapter-0`](#slide-chapter-0) | 附录 | 第一次做奇域需要知道什么? | 0 |  |
| 26 | [`client-server`](#slide-client-server) | 附录 | 服务端、客户端 | 0 | ✓ |
| 27 | [`level-settings`](#slide-level-settings) | 附录 | 关卡设置 | 2 |  |
| 28 | [`settlement`](#slide-settlement) | 附录 | 结算 | 3 | ✓ |
| 29 | [`logs`](#slide-logs) | 附录 | 日志 | 1 |  |
| 30 | [`assets`](#slide-assets) | 附录 | 资产导入及使用 | 1 |  |
| 31 | [`entities`](#slide-entities) | 附录 | 关卡、玩家实体 | 0 | ✓ |
| 32 | [`variables-nodes`](#slide-variables-nodes) | 附录 | 自定义变量与节点图 | 2 | ✓ |
| 33 | [`signal-nodes`](#slide-signal-nodes) | 附录 | 用信号连接两端 | 1 | ✓ |
