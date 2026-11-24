# `tools/` —— 脚本唯一入口（★ 本机只认这里 ✓）

> ★★★ **正式脚本只从本目录跑** ✓ —— ★ 工作区里其它位置的同名脚本都是**副本或历史快照** ✗
> ★★ 原因 ✓：★ 历史上出现过同名脚本最多 **24 份**（`init.lua`）／19 份（`main.lua`）／16 份（`ui_controller.lua`）✗
> 　 ⇒ ★ 跑错副本会得到"改了没效果"或"版本不对"的假象 ✓

## 一 ★★ 常用入口（★ 记住这几条就够）

| 要做 | 跑这个 |
|---|---|
| ★ 打包客户端脚本 | ★ `lua tools/bundle_client_script.lua` ✓ |
| ★ 关卡唯一解闸门 | ★ `lua tools/validate_levels.lua` ✓ |
| ★ 升构建标记 | ★ `node tools/bump_build_marker.mjs` ✓ |
| ★ `.gil` 体检 | ★ `node tools/gil/inspect_gil.mjs <存档>` ✓ |
| ★ 编码闸门 | ★ `node tools/check_encoding.mjs` ✓ |
| ★ 全量检查 | ★ `pwsh tools/check_all.ps1` ✓ |

## 二 ★★ 目录约定

- ★ `tools/gil/` —— `.gil` 读写与体检（★ 正式工具 ✓；`_` 前缀是一次性探针 ✗）
- ★ `tools/sim/` —— 模拟器/试玩
- ★ `tools/audit/` —— 代码审计
- ★ `tools/qx/` —— 千星侧探针与素材
- ★ **`_` 开头的脚本 = 一次性探针** ✗（留着当证据，不要当日常工具 ✓）
- ★ **`_wip/`、`out/` = 生成物/草稿** ✗（不入库、也别当入口 ✓）

## 三 ★ 发现重复脚本怎么办

```powershell
cd "D:\新建文件夹\miHoYo Launcher"
pwsh -File .\工作区体检.ps1
```
★ 它会列出 **同名但内容不同** 的文件 ✓ —— ★ 一律以 `qianxing-murdoku\tools\` 那份为准 ✓
