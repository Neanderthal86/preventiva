# ============================================================
# Tech Fontes - Preventiva Corporativa Windows (One-Line Runner)
# Uso: irm https://raw.githubusercontent.com/Neanderthal86/preventiva/main/run.ps1 | iex
# ============================================================

$ErrorActionPreference = "Stop"

$RepoZipUrl = "https://github.com/Neanderthal86/preventiva/archive/refs/heads/main.zip"
$RawRunUrl  = "https://raw.githubusercontent.com/Neanderthal86/preventiva/main/run.ps1"
$InstallDir = "C:\ProgramData\TechFontes\Preventiva"

# 1. Eleva automaticamente para Administrador se necessario
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "[TECH FONTES] Solicitando privilegios de Administrador..." -ForegroundColor Yellow
    $cmd = "irm '$RawRunUrl' | iex"
    Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"$cmd`"" -Verb RunAs
    return
}

# 2. Baixa e extrai a versao mais recente da pasta Dist/
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$tempRoot = Join-Path $env:TEMP ("TechFontes_Preventiva_" + [guid]::NewGuid().ToString("N"))
$zipPath  = Join-Path $tempRoot "preventiva.zip"
$extPath  = Join-Path $tempRoot "extracted"

try {
    Write-Host "[TECH FONTES] Baixando versao mais recente da Preventiva..." -ForegroundColor Cyan
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    Invoke-WebRequest -Uri $RepoZipUrl -OutFile $zipPath -UseBasicParsing

    Write-Host "[TECH FONTES] Extraindo arquivos..." -ForegroundColor Cyan
    Expand-Archive -Path $zipPath -DestinationPath $extPath -Force

    $repoFolder = Get-ChildItem -LiteralPath $extPath -Directory | Select-Object -First 1
    $distSource = Join-Path $repoFolder.FullName "Dist"
    if (-not (Test-Path -LiteralPath $distSource)) {
        throw "Pasta Dist nao encontrada no pacote baixado."
    }

    if (Test-Path -LiteralPath $InstallDir) {
        Remove-Item -LiteralPath $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
    }
    New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
    Copy-Item -Path (Join-Path $distSource "*") -Destination $InstallDir -Recurse -Force

    $panelScript = Join-Path $InstallDir "Painel-Preventiva.ps1"
    if (-not (Test-Path -LiteralPath $panelScript)) {
        throw "Painel-Preventiva.ps1 nao encontrado em $InstallDir"
    }

    Write-Host "[TECH FONTES] Abrindo Painel da Preventiva..." -ForegroundColor Green
    Start-Process powershell.exe -ArgumentList "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$panelScript`""
} finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
