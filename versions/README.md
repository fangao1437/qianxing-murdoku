# versions\ —— 每轮一份"脚本 + 存档"快照（回退用）

> 2026-10-02 建立。起因：这一轮回退时想找"之前能跑的那一版"，
> 结果**只能去 git 里挖，而 git 里的 `.gil` 和我实际交付的不是同一份**
> （git 的 `完整界面124-补回主体组.gil` 只有 69 条记录，用户手上那份有 91 条 + 6 个素材）。
>
> 根因是我每轮都用 `Remove-Item` 删旧 `.gil`、只留一份"最新"，脚本也只存在工作区里被下一轮直接改掉。

## 规则（**从 001 起，每轮都遵守**）

1. **`.gil` 每轮用新名字留在磁盘上** —— **不删、不覆盖**。旧版本永远能在工作区找到。
2. **脚本每轮整份归档到 `versions\<编号>-<说明>\`** —— 含 7 个源文件 + `client_script.lua`（**真机跑的那份**）+ 配套 `.gil` + `MANIFEST.txt`。
3. **git 照常提交**，但它**不再是唯一的回退手段**。
4. **回退步骤**：把该目录的 `*.lua` 拷回 `lua\` → `node tools/bundle_client_script.lua` →
   `powershell -File tools/install_script_to_sandbox.ps1` → 导入该目录里的 `.gil`。

## 归档命令

```powershell
node tools/archive_version.mjs --name="002-xxx" --gil="完整界面131-xxx.gil" --note="这一轮做了什么"
```

（用 Node 而不是 PowerShell 脚本：`.ps1` 带中文时 Windows PowerShell 5.1 会按 ANSI 读，
全角引号/括号会直接把解析器搞崩 —— 本轮踩了两次。）

## 已有版本

| 编号 | 内容 | 配套 .gil |
|---|---|---|
| **001** | **回退到用户测过的 124**（91 条记录 + 6 个转存素材模板）；脚本倒回 git `6e3dcbc` | `完整界面130-回到124含资产.gil` |