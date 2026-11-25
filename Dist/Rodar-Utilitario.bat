@echo off
:: Solicitar Privilegios Administrativos
net session >nul 2>&1
if %errorLevel% == 0 (
    goto :RunPowerShell
) else (
    echo Solicitando privilegios administrativos...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit
)

:RunPowerShell
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "TechFontes-Utility.ps1"
exit
