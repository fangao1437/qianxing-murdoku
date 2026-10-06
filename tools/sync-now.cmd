@echo off
chcp 65001 >nul
echo ============================================
echo  Syncing client_script.lua into every game save root
echo ============================================
powershell -ExecutionPolicy Bypass -File "%~dp0install_script_to_sandbox.ps1"
echo.
echo Check: the "synced N root(s)" line, and every root must show the same byte count.
echo If a NEW root appeared (new level), run this again.
echo.
pause