@echo off
setlocal
rem Start the GUI in its own process, then release this batch file before any move.
if not exist "%~dp0app\UserSpace.ps1" (
    echo Missing program files. Please extract the complete ZIP package.
    pause
    exit /b 1
)
start "" /d "%TEMP%" "%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoLogo -NoProfile -STA -WindowStyle Hidden -ExecutionPolicy Bypass -File "%~dp0app\UserSpace.ps1"
exit /b

