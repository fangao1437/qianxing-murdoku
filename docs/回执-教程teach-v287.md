# 回执 —— 教程浮层改造：teach 容器 + 两关各一套 + 文本归编辑器（v287 / 2026-10-21）

> 用户本轮（真机导入成功后）：「并入成功，现在开始修改教程，本轮目标有三个，
> ① 清理掉上方的三个分类按键，只保留页面本身和翻页功能；
> ② 文本按照工作约定交由编辑器，把所有教程相关控件放到一个新容器 teach 下，所有文本则再在 teach 下建一个区域来容纳；
> ③ 把教程的弹出接到第一关和第二关内部（注，两关后续要加的内容不同，不要用同一套接两个地方）。」
>
> 基线：★ `472.gil`（v286 那版 `482` 已验证"导入不报错"，它与 472 的差别只有我们自己的教程控件，
> 所以结构重建仍然以 472 为基线最干净）
> 交付：★ **`483-教程teach-v287.gil`**（409 条 = 371 + 38 / 内嵌脚本 v287）

---

## 一 三条要求各自怎么落地

| # | 要求 | 落地 |
|---|---|---|
| ① | 清理上方三个分类按键，只留页面本体与翻页 | 页签 `tab.p1..3` / `state.sel` **全部不再生成**；每关只剩：页面本体（`*.page` + `*.page.bg`）、`上一页` / `下一页` / `关闭` 三个按钮（`关闭` 保留 —— 否则教程弹出来没法收起）。`重置` 也一起去掉（翻页能回到第 1 页） |
| ② | 文本交编辑器；教程控件收进 `teach`；文本再在 `teach` 下建一个区域 | 新结构见 §二：顶层新容器 **`teach`**；其下 `teach.l1` / `teach.l2`（面板 + 翻页 + 关闭）与 **`teach.text`**（文本区域，内分 `teach.text.l1` / `teach.text.l2`）。★ **脚本一个字都不写**：不做 `SetText` / `.text=`，只做显隐与绑定（离线测试用"记账 setter"断言写入次数 = 0） |
| ③ | 弹出接到第一关、第二关内部，两关各一套 | 每关**一个实例、一段配置**：`TUT_LEVELS = { case_001 = {...l1...}, case_002 = {...l2...} }`；`tick_tutorial` 每帧读当前关卡 id（`Murdoku.current()` → `level.id`），进哪一关弹哪一套、离开就收起，**共享的只有"每帧调用"这一处**，内容与实例不共用 |

## 二 新存档结构（全部由 472 母本克隆，号段 1073743900…1073743937）

```
teach                          容器 1600×900，父 = root
├ teach.l1                     第 1 关教程面板 1240×780
│   ├ teach.l1.bg              图片（铺满）
│   ├ teach.l1.page            页面本体 1120×380 → teach.l1.page.bg（图片，铺满）
│   ├ teach.l1.btn.prev / .next / .close      预设按钮（各自带子控件 bg）
├ teach.l2                     第 2 关教程面板（同上）
└ teach.text                   文本区域 1600×900
    ├ teach.text.l1            第 1 关文本分区
    │   ├ title                标题（编辑器填）
    │   ├ body.1 / body.2 / body.3   三页正文（按页显隐；编辑器填）
    │   └ btn.prev / btn.next / btn.close   按钮字（编辑器填，位置叠在对应按钮上）
    └ teach.text.l2            第 2 关文本分区（同上 7 条）
```

38 条记录 = 28 个控件 + 10 个按钮/面板底图子控件。

## 三 脚本侧（本轮改）

| 文件 | 改动 |
|---|---|
| `lua/tutorial_ui.lua` | 重写：`M.new(adapter, {tag, root, text, pages})`；`init/open/close/goto/next/prev`；**不再有页签、页码、文案表，不写任何文字**；页数由 `pages` 决定（现在 3） |
| `lua/entry_client_script.lua` | v287 接线：两套实例（`tutorial_inst[tag]`）+ 两段配置（`TUT_LEVELS`）+ 按当前关卡 id 弹/收；两套各自跑一次自检；"根容器 ~2 秒没进树"仍兜底自检 |
| `lua/tut_verify.lua` | 期望清单换成 `teach.*` 新名字（含 L1/L2 两套的关键控件） |
| `tests/tutorial_ui.lua` / `tests/tut_verify.lua` | 跟着新语义重写/调整，全绿 |

## 四 交付链

```
472.gil
  → node tools/gil/gen_tutorial_teach.mjs --base=472.gil --out=tools/gil/out/483-controls.gil   # 409 条
  → lua tools/bundle_client_script.lua                                                          # dist
  → node tools/lua53check/check.cjs dist/client_script.lua --run                                # LOAD+RUN OK
  → node tools/gil/embed_script.mjs --in=tools/gil/out/483-controls.gil \
        --out=483-教程teach-v287.gil --expect-marker=v287                                        # 内嵌 v287
```

## 五 验收证据

| # | 判据 | 结果 |
|---|---|---|
| 1 | 撞号 / 自身 GUID / 父子表 | ✅ 0 撞号、两处一致、父子表一致（`probe_guid_collision`） |
| 2 | 母本链与族号（v286 真因所在） | ✅ 悬空 0、撞族 0、退出码 0（`probe_ui_registry --base=472-头像层-v283.gil`） |
| 3 | 只加不改 | ✅ 相对 472 差异 2 处（记录数组 + `root` 子列表） |
| 4 | 新记录零外来 id | ✅ 生成器断言（只允许自己/父/子控件的号） |
| 5 | 往返 | ✅ 逐字节一致 |
| 6 | 离线 | ✅ `tutorial_ui` / `tut_verify` 全绿、`lua53check` LOAD+RUN OK |
| 7 | 内嵌脚本标记 | ✅ v287（源码/dist/内嵌三处一致） |
| 8 | 真机 | ⏳ 待导入 `483-教程teach-v287.gil`（详见 `docs/真机导入-483-v287.md`） |

## 六 你要做的（两步）

1. **导入 `483-教程teach-v287.gil`**（导入应当不报错 —— 结构与 v286 同源）。
2. **在编辑器里填文字**（`.gil` 存不下文字，这是工作约定）：
   `teach.text.l1.title` / `body.1..3` / `btn.prev|next|close`，以及 `teach.text.l2` 同名 7 条。
   填完之后游戏里就是这些字 —— **脚本不会再覆盖你的文字**。
3. 进第一关看 L1 教程弹出、第二关看 L2 教程弹出；日志首屏应有 `[tut] 自检 OK N/N`。

## 七 已知未验证 / 待用户确认

| 项 | 状态 |
|---|---|
| 真机导入与两关弹出 | ⏳ 待你验 |
| 文本区域与按钮字的位置是否合用（现在按设计稿坐标摆放） | ⏳ 真机看一眼；不合适我改坐标，不用你手动挪 |
| 每关页数（现在都按 3 页给） | ⏳ 以后哪关要几页告诉我，我按 `TUT_LEVELS` 里那一关单独加 |
| `关闭` 保留 | ★ 我按"没关闭就没法收起"处理；若你要连 `关闭` 也去掉（改成点任意处收起 / 或只在看完最后一页自动关），说一声 |
