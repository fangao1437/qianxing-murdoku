@echo off
chcp 65001 >nul
echo 当前根目录的最新存档：
for /f "delims=" %%f in ('dir /b /o-d *.gil 2^>nul') do (
  echo   %%f
  goto :done
)
:done
echo.
echo 旧存档都在「存档归档」文件夹里。
echo 脚本快照都在「versions」文件夹里（每个版本一个子目录）。
pause
