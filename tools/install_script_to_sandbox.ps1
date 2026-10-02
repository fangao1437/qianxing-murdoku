# tools/install_script_to_sandbox.ps1
# Copy the bundled client script into the sandbox "script root" folder(s).
#
# IMPORTANT (this is the bug that cost hours):
#   The LIVE script root is under  %USERPROFILE%\AppData\LocalLow\miHoYo\...
#   NOT under %LOCALAPPDATA% (\AppData\Local\miHoYo\...).
#   Genshin keeps its real player/editor data in LocalLow; the Local tree is only
#   created if someone copies files there by mistake, and the editor's file picker
#   will then show an EMPTY folder ("no items match your search").
#
#   Root layout (one per level save id):
#     C:\Users\<you>\AppData\LocalLow\miHoYo\<game>\BeyondLocal\<uid>\
#         Beyond_Local_Save_Level\<levelSaveId>\external_lua_file\
#
#   This script searches BOTH LocalLow (preferred) and Local, and syncs into every
#   external_lua_file folder it finds. Re-run it whenever the level save id changes.
#
# Usage (from the project root):
#   powershell -ExecutionPolicy Bypass -File tools\install_script_to_sandbox.ps1
#
# Note: keep this file free of non-ASCII in strings; paths with CJK are matched
#       with wildcards so PowerShell 5.1 encoding cannot break them.

$ErrorActionPreference = 'Continue'

# Locate project root: prefer the script's own location; fall back to cwd.
$root = $PSScriptRoot
if ($root) { $root = Split-Path -Parent $root } else { $root = (Get-Location).Path }
$src  = Join-Path $root 'dist\client_script.lua'

if (-not (Test-Path $src)) {
  Write-Output ("bundle not found: " + $src)
  Write-Output "run first:  lua tools\bundle_client_script.lua"
  exit 1
}
$srcLen = (Get-Item $src).Length
Write-Output ("source : " + $src + "  (" + $srcLen + " bytes)")

# Candidate miHoYo data roots, LocalLow first (that is the live one).
$bases = @(
  (Join-Path $env:USERPROFILE 'AppData\LocalLow\miHoYo'),
  (Join-Path $env:LOCALAPPDATA 'miHoYo')
)

$found = @()
foreach ($b in $bases) {
  if (Test-Path $b) {
    $hit = Get-ChildItem -Path $b -Directory -Recurse -Filter 'external_lua_file' -ErrorAction SilentlyContinue
    if ($hit) { $found += $hit }
  }
}

if (-not $found) {
  Write-Output "no script root (external_lua_file) found."
  Write-Output "fix: open Client Script Resource Manager in the editor once, then re-run."
  exit 2
}

# LocalLow first, then Local; drop duplicates.
$ordered = @()
foreach ($prefer in @('LocalLow','Local')) {
  foreach ($d in $found) {
    if ($d.FullName -like ('*\' + $prefer + '\*')) {
      if ($ordered -notcontains $d.FullName) { $ordered += $d.FullName }
    }
  }
}
foreach ($d in $found) { if ($ordered -notcontains $d.FullName) { $ordered += $d.FullName } }

$n = 0
foreach ($dir in $ordered) {
  $tag = 'Local'
  if ($dir -like '*\LocalLow\*') { $tag = 'LocalLow' }
  $dst = Join-Path $dir 'client_script.lua'
  Copy-Item -Path $src -Destination $dst -Force -ErrorAction SilentlyContinue
  if (-not (Test-Path $dst)) {
    Write-Output ("[" + $tag + "] FAILED  -> " + $dir)
    continue
  }
  # ★★★★★ 2026-10-02 **BOM 必须剥掉**。
  #
  #   引擎日志（`%LOCALAPPDATA%Low\miHoYo\原神\output_log.txt`，2026-10-02 22:39:47）写着：
  #       Read text file with BOM header may cause Lua error, file is 93b17eac / f668c022 / 2109080b
  #   而当天真的踩到了：`Beyond_Local_Save_Level\1073741929\external_lua_file\client_script.lua`
  #   比别处多 **正好 3 字节**（EF BB BF）⇒ 那一份是**带 BOM 的**，而用户当时测的就是它。
  #   ⇒ 每次同步后**就地检查并剥掉**，并且**写回后再验一次**（不能只信"我剥了"）。
  $bytes = [System.IO.File]::ReadAllBytes($dst)
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    [System.IO.File]::WriteAllBytes($dst, $bytes[3..($bytes.Length - 1)])
    $after = [System.IO.File]::ReadAllBytes($dst)
    $stillBom = ($after.Length -ge 3 -and $after[0] -eq 0xEF -and $after[1] -eq 0xBB -and $after[2] -eq 0xBF)
    Write-Output ("[" + $tag + "] BOM 已剥掉 -> " + $dst + "  (" + $bytes.Length + " -> " + $after.Length + " bytes, 复查=" + $(if ($stillBom) { '★还在' } else { 'OK' }) + ")")
  }
  # 源文件自己也不能带 BOM（否则每次都得靠上面这段补救）
  if ($srcLen -ne (Get-Item $dst).Length) {
    Write-Output ("[" + $tag + "] 大小不一致 -> " + (Get-Item $dst).Length + " vs 源 " + $srcLen)
  }
  $h = (Get-FileHash $dst -Algorithm SHA256).Hash
  $ok = 'HASH-MISMATCH'
  if ((Get-Item $dst).Length -eq $srcLen) { $ok = 'ok' }
  Write-Output ("[" + $tag + "] synced  -> " + $dst + "  (" + (Get-Item $dst).Length + " bytes, " + $ok + ")")
  $n++
}

Write-Output ("done: synced " + $n + " root(s).")
Write-Output "back in the editor: Client Script Resource Manager -> the script record -> edit the file path -> pick client_script.lua"
Write-Output "if the picker is already open, click the refresh (circular arrow) button."
