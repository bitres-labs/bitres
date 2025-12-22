@echo off
REM BRS system - Port forwarding setup (batch launcher)
REM Automatically runs the PowerShell script as Administrator

echo ========================================
echo BRS port forwarding setup
echo ========================================
echo.
echo Launching PowerShell as Administrator...
echo.

REM Get current script directory
set SCRIPT_DIR=%~dp0

REM Run PowerShell script as Administrator
PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& {Start-Process PowerShell -ArgumentList '-NoProfile -ExecutionPolicy Bypass -File ""%SCRIPT_DIR%setup-port-forwarding.ps1""' -Verb RunAs}"

echo.
echo If no PowerShell window appears, run manually as Administrator:
echo %SCRIPT_DIR%setup-port-forwarding.ps1
echo.
pause
