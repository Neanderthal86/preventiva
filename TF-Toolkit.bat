@echo off
:: ============================================
:: TECH FONTES - TF-Toolkit v3.0
:: ============================================

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [TECH FONTES] Solicitando privilegios de Administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

set SCRIPT=%~dp0TF-Toolkit.ps1
if not exist "%SCRIPT%" (
    echo [ERRO] Script principal nao encontrado em: %SCRIPT%
    pause
    exit /b 1
)

powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
exit /b
