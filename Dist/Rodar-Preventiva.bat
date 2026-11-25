@echo off
:: ============================================
:: TECH FONTES - Preventiva Corporativa Windows
:: (Launcher do Painel Visual)
:: ============================================

:: Verifica se esta rodando como Administrador
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [TECH FONTES] Elevando privilegios de Administrador...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

:: Caminho do painel
set SCRIPT=%~dp0Painel-Preventiva.ps1

if not exist "%SCRIPT%" (
    echo.
    echo  [ERRO] Script do painel nao encontrado em:
    echo  %SCRIPT%
    echo.
    pause
    exit /b 1
)

:: Oculta a janela preta atual e abre o Painel Visual
powershell -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%"
exit /b
