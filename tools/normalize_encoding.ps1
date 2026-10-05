# tools/normalize_encoding.ps1 -- fix UTF-8 BOM state for all source files.
#
# WHY THIS EXISTS
#   Two opposite rules, both easy to violate by accident:
#
#     .ps1 WITH non-ASCII  -> MUST have UTF-8 BOM.
#         Windows PowerShell 5.1 reads a BOM-less file as GBK, so Chinese
#         text turns into mojibake and the parser then dies on things like
#         "The string is missing the terminator" at a line that looks fine.
#
#     .lua / .md           -> MUST NOT have BOM.
#         The bundler concatenates all modules into ONE chunk. A BOM in the
#         middle of that chunk makes Lua 5.3 report
#         "unexpected symbol near '<\239>'" at end-of-file, which is almost
#         impossible to connect back to the real cause.
#
#   The `edit` tool strips the BOM on every write, so after editing any
#   non-ASCII .ps1 you have to put it back. Run this script instead of
#   doing it by hand.
#
# USAGE (from the project root)
#   powershell -ExecutionPolicy Bypass -File tools\normalize_encoding.ps1
#   powershell -ExecutionPolicy Bypass -File tools\normalize_encoding.ps1 -Check
#
#   -Check  : report only, change nothing, exit 1 if anything is wrong.
#
# This file is deliberately pure ASCII so that it needs no BOM itself.

param([switch]$Check)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

$utf8Bom    = New-Object System.Text.UTF8Encoding($true)
$utf8NoBom  = New-Object System.Text.UTF8Encoding($false)

$changed = 0
$problems = 0

function Test-NonAscii([string]$text) {
  foreach ($ch in $text.ToCharArray()) { if ([int]$ch -gt 127) { return $true } }
  return $false
}

$files = Get-ChildItem -Path $root -Recurse -File -Include *.ps1, *.lua, *.md |
  Where-Object { $_.FullName -notmatch '\\node_modules\\' }

foreach ($f in $files) {
  $bytes = [System.IO.File]::ReadAllBytes($f.FullName)
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 239 -and $bytes[1] -eq 187 -and $bytes[2] -eq 191)
  $text = [System.IO.File]::ReadAllText($f.FullName)
  $nonAscii = Test-NonAscii $text
  $ext = $f.Extension.ToLower()
  $rel = $f.FullName.Substring($root.Length + 1)

  $wantBom = $false
  if ($ext -eq '.ps1' -and $nonAscii) { $wantBom = $true }

  if ($wantBom -eq $hasBom) { continue }

  $problems++
  if ($hasBom -and -not $wantBom) {
    Write-Host ("[STRIP-BOM] {0}" -f $rel)
  } else {
    Write-Host ("[ADD-BOM  ] {0}  (non-ASCII text)" -f $rel)
  }

  if (-not $Check) {
    $enc = if ($wantBom) { $utf8Bom } else { $utf8NoBom }
    [System.IO.File]::WriteAllText($f.FullName, $text, $enc)
    $changed++
  }
}

if ($Check) {
  if ($problems -gt 0) {
    Write-Host ""
    Write-Host ("{0} file(s) have the wrong BOM state. Run without -Check to fix." -f $problems)
    exit 1
  }
  Write-Host "encoding: all files OK"
  exit 0
}

if ($changed -eq 0) {
  Write-Host "encoding: already correct, nothing to do"
} else {
  Write-Host ("encoding: fixed {0} file(s)" -f $changed)
}
exit 0
