@echo off
:: ============================================
:: TECH FONTES - TF-Toolkit v4.0 (Launcher GUI)
:: ============================================
start "" /b powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -STA -File "%~dp0WinForge.Gui.ps1"
exit /b
