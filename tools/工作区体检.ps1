# 工作区体检.ps1 —— 检查「仓库状态 / 重复脚本 / 根目录散件」
# 用法：在根目录跑  pwsh -File .\工作区体检.ps1        （加 -Full 显示全部）
param([switch]$Full)

$ErrorActionPreference = 'Continue'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $base
$main = Join-Path $base 'qianxing-murdoku'
$tools = Join-Path $main 'tools'

function Line($t) { Write-Host $t }
$bad = 0

Line ''
Line '════════ 工作区体检 ════════'
Line ('根目录: ' + $base)
Line ''

# ── ① 五个仓库 ─────────────────────────────────────────────
Line '── ① 仓库状态 ─────────────────────────'
$repos = @('qianxing-murdoku','qianxing-murdoku-old','qianxing-murdoku-tool','murdoku-project','murdoku-pro')
foreach ($r in $repos) {
  $p = Join-Path $base $r
  if (-not (Test-Path (Join-Path $p '.git'))) { Line ('  ⚠️ ' + $r + '：没有 .git（★ 缺仓）'); $bad++; continue }
  $branch = (& git -C $p rev-parse --abbrev-ref HEAD 2>$null)
  $head = (& git -C $p rev-parse --short HEAD 2>$null)
  if (-not $head) { Line ('  ⏳ ' + $r + '：克隆/检出未完成（HEAD 为空）'); $bad++; continue }
  $up = (& git -C $p rev-parse --short '@{u}' 2>$null)
  $dirty = (@(& git -C $p -c core.quotepath=false status --porcelain 2>$null)).Count
  $hasUp = ($up -and $up -notmatch 'fatal|error')
  $sync = if ($hasUp -and $head -eq $up) { '✅' } else { '⚠️' }
  Line ('  ' + $sync + ' ' + $r + '：' + $branch + ' @ ' + $head + '  上游 ' + $(if ($hasUp) { $up } else { '（无）' }) + '  未提交 ' + $dirty)
  if ($dirty -gt 0) { $bad++ }
  if (-not $hasUp) { $bad++ }
}

# ── ② worktree ────────────────────────────────────────────
Line ''
Line '── ② 主仓 worktree（应为 1 个）─────────'
if (Test-Path (Join-Path $main '.git')) {
  $wts = @(& git -C $main worktree list 2>$null)
  Line ('  共 ' + $wts.Count + ' 个')
  foreach ($w in $wts) { Line ('    ' + $w) }
  if ($wts.Count -gt 1) { Line '  ⚠️ 多于 1 个 ⇒ 旧的请退役（防拿错脚本）'; $bad++ }
}

# ── ③ 外部脚本副本 vs 主仓 tools ───────────────────────────
Line ''
Line '── ③ 主仓 tools 之外的脚本副本（★ 拿错脚本的根因）──'
$skipRx = '\\(\.git|node_modules|_vendor|games|_trash|__pycache__)\\|\\1\.2[0-9]\.'
$canon = @{}
if (Test-Path $tools) {
  Get-ChildItem $tools -Recurse -File -Include '*.mjs','*.ps1','*.py','*.lua','*.cjs' -ErrorAction SilentlyContinue |
    ForEach-Object { if (-not $canon.ContainsKey($_.Name)) { $canon[$_.Name] = $_.FullName } }
}
$outside = Get-ChildItem $base -Recurse -File -Include '*.mjs','*.ps1','*.py','*.lua','*.cjs' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch $skipRx -and $_.FullName -notlike ($main + '\*') }
$sameName = @()
foreach ($f in $outside) {
  if ($canon.ContainsKey($f.Name)) {
    $h1 = (Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
    $h2 = (Get-FileHash -LiteralPath $canon[$f.Name] -Algorithm SHA256 -ErrorAction SilentlyContinue).Hash
    if ($h1 -ne $h2) {
      $sameName += [pscustomobject]@{ Name = $f.Name; Where = $f.FullName.Replace($base + '\', '') }
    }
  }
}
Line ('  主仓 tools 内脚本名 ' + $canon.Count + ' 个；外部有同名副本 ' + $sameName.Count + ' 份')
$show = if ($Full) { $sameName } else { $sameName | Select-Object -First 15 }
foreach ($s in $show) { Line ('    ⚠️ ' + $s.Name + '  ← ' + $s.Where) }
if ($sameName.Count -gt 0) {
  Line '  ★ 一律以 `qianxing-murdoku\tools\` 那份为准；外部副本不要跑'
  $bad++
}

# ── ④ 根目录散件 ───────────────────────────────────────────
Line ''
Line '── ④ 根目录散件（应只有导航/体检/安装器）──'
$allowed = @('工作区导航.md','工作区体检.ps1','config.ini','launcher.exe','uninstall.exe','vc_redist.x64.exe')
$stray = Get-ChildItem $base -File | Where-Object { $allowed -notcontains $_.Name }
if ($stray.Count -eq 0) { Line '  ✅ 无散件' } else {
  foreach ($s in $stray) { Line ('  ⚠️ ' + $s.Name + '（' + [math]::Round($s.Length / 1MB, 2) + 'MB）') }
  Line '  ★ 收进 构建存档\ / 报告\ / 设计资料\ 或删除'
  $bad++
}
$strayDirs = Get-ChildItem $base -Directory | Where-Object { $_.Name -match '^\d{3}_' }
foreach ($d in $strayDirs) { Line ('  ⚠️ 根目录构建目录：' + $d.Name + '（应并入 构建存档\ 或主仓）'); $bad++ }

# ── ⑤ 回收站 ──────────────────────────────────────────────
Line ''
Line '── ⑤ 回收站 ───────────────────────────'
$trash = Join-Path $base '_work\_trash'
if (Test-Path $trash) {
  $mb = [math]::Round(((Get-ChildItem $trash -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum) / 1MB, 1)
  Line ('  _work\_trash = ' + $mb + 'MB' + $(if ($mb -gt 500) { '  ⚠️ 建议清空' } else { '' }))
} else { Line '  （无回收站）' }

Line ''
Line '════════ 结论 ════════'
if ($bad -eq 0) { Line '✅ 全部通过'; exit 0 } else { Line ('⚠️ 有 ' + $bad + ' 项待处理（见上）'); exit 1 }
